import Agentic

/// Parent-owned admission state for a tree of Agent invocations.
///
/// This actor reserves *authority*, not execution. A child runner must be
/// launched through the governed Runtime path after admission, and its final
/// outcome must settle the reservation. Pending or suspended children stay
/// active. No model input can construct or select a parent origin here.
public actor AgentDelegation {
    public struct Session: Sendable, Codable, Hashable {
        public let id: String
        public let agent: AgentIdentifier
        public let parentSessionID: String?
        public let depth: Int

        init(
            id: String,
            agent: AgentIdentifier,
            parentSessionID: String?,
            depth: Int
        ) {
            self.id = id
            self.agent = agent
            self.parentSessionID = parentSessionID
            self.depth = depth
        }
    }

    public enum Failure: Error, Sendable {
        case unknownSession(String)
        case duplicateSession(String)
        case settledSession(String)
        case disabled(AgentIdentifier)
        case notInstalled(AgentIdentifier)
        case notAvailable(AgentIdentifier)
        case notAllowed(AgentIdentifier)
        case reentry(AgentIdentifier)
        case depthExceeded(AgentIdentifier)
        case childLimitExceeded(AgentIdentifier)
        case descendantLimitExceeded(AgentIdentifier)
        case concurrencyLimitExceeded(AgentIdentifier)
        case activeDescendants(String)
        case nonterminalResult(String)
        case executionAlreadyStarted(String)
        case executionInProgress(String)
        case executionNotStarted(String)
        case resultIdentityMismatch(expected: String, actual: String)
    }

    private struct Entry: Sendable {
        let session: Session
        let realization: AgentRealization
        let capabilities: AgentCapabilityState
        var settled: Bool
        var runner: AgentRunner? = nil
        var executing: Bool = false
    }

    private let runtime: AgenticRuntime
    private let installed: InstalledCapabilities
    private var entries: [String: Entry]

    /// The root's live capability state should be the same state held by its
    /// AgentRunner. Runtime composition is responsible for sharing that actor.
    public init(
        runtime: AgenticRuntime,
        root: AgentIdentifier,
        sessionID: String,
        capabilityState: AgentCapabilityState
    ) throws {
        let realization = try runtime.realizeAgent(identifiedBy: root)
        let session = Session(
            id: sessionID,
            agent: root,
            parentSessionID: nil,
            depth: 0
        )
        self.runtime = runtime
        installed = runtime.installed
        entries = [
            sessionID: Entry(
                session: session,
                realization: realization,
                capabilities: capabilityState,
                settled: false
            )
        ]
    }

    public func session(_ id: String) -> Session? {
        entries[id]?.session
    }

    /// Atomically reserve a child under the parent's current authority.
    /// Quotas count all admitted children, including completed ones, except
    /// concurrency, which counts only unsettled direct children.
    public func begin(
        _ agent: AgentIdentifier,
        from parentSessionID: String,
        sessionID: String
    ) async throws -> Session {
        guard let observedParent = entries[parentSessionID] else {
            throw Failure.unknownSession(parentSessionID)
        }
        let available = await observedParent.capabilities.snapshot().available

        // Actor reentrancy may have occurred across the await. The complete
        // session tree is checked only after the live snapshot is acquired.
        guard let parent = entries[parentSessionID] else {
            throw Failure.unknownSession(parentSessionID)
        }
        guard !parent.settled else {
            throw Failure.settledSession(parentSessionID)
        }
        guard entries[sessionID] == nil else {
            throw Failure.duplicateSession(sessionID)
        }
        let policy = parent.realization.delegation
        guard policy.enabled else {
            throw Failure.disabled(parent.session.agent)
        }
        guard available.agents.contains(agent) else {
            throw Failure.notAvailable(agent)
        }
        let allowed = installed.catalog.resolve(
            AgentCapabilityScope(agents: policy.allowedAgents)
        ).agents
        guard allowed.contains(agent) else {
            throw Failure.notAllowed(agent)
        }
        guard let binding = installed.agentBinding(agent) else {
            throw Failure.notInstalled(agent)
        }

        let ancestry = try lineage(from: parentSessionID)
        let depth = parent.session.depth + 1
        for ancestor in ancestry {
            let limits = ancestor.realization.delegation.limits
            guard depth - ancestor.session.depth <= limits.depth else {
                throw Failure.depthExceeded(agent)
            }
            let descendants = entries.values.filter {
                isDescendant($0.session, of: ancestor.session.id)
            }.count
            guard descendants < limits.descendants else {
                throw Failure.descendantLimitExceeded(agent)
            }
            switch ancestor.realization.delegation.reentry {
            case .deny_ancestor_definition:
                guard !ancestry.contains(where: { $0.session.agent == agent }) else {
                    throw Failure.reentry(agent)
                }
            case .allow_same_definition(let maxOccurrences):
                let occurrences = ancestry.filter { $0.session.agent == agent }.count
                guard occurrences + 1 <= maxOccurrences else {
                    throw Failure.reentry(agent)
                }
            }
        }

        let direct = entries.values.filter {
            $0.session.parentSessionID == parentSessionID
        }
        guard direct.count < policy.limits.children else {
            throw Failure.childLimitExceeded(agent)
        }
        guard direct.filter({ !$0.settled }).count < policy.limits.concurrentChildren else {
            throw Failure.concurrencyLimitExceeded(agent)
        }

        let session = Session(
            id: sessionID,
            agent: agent,
            parentSessionID: parentSessionID,
            depth: depth
        )
        let child = AgentRealization.materialize(
            definition: binding.definition,
            installed: installed
        )
        entries[sessionID] = Entry(
            session: session,
            realization: child,
            capabilities: child.makeCapabilityState(),
            settled: false
        )
        return session
    }

    /// Settle only a terminal child. The eventual caller must retain the
    /// reservation when the child suspends, awaits approval or is interruptible.
    public func settle(_ result: AgentRunner.Result) throws {
        let sessionID = result.sessionID
        guard result.isCompleted || result.isFailed else {
            throw Failure.nonterminalResult(sessionID)
        }
        guard var entry = entries[sessionID] else {
            throw Failure.unknownSession(sessionID)
        }
        guard !entry.settled else {
            throw Failure.settledSession(sessionID)
        }
        guard !entry.executing else {
            throw Failure.executionInProgress(sessionID)
        }
        guard !entries.values.contains(where: {
            !$0.settled && isDescendant($0.session, of: sessionID)
        }) else {
            throw Failure.activeDescendants(sessionID)
        }
        entry.settled = true
        entries[sessionID] = entry
    }

    /// Trusted Runtime path: admit, construct, and execute the child using the
    /// exact realization and live capability actor retained by this tree.
    /// The child's runner is retained for subsequent checkpoint resumption.
    /// Suspension and interruption never settle its reservation.
    public func run(
        _ agent: AgentIdentifier,
        request: AgentRequest,
        from parentSessionID: String,
        sessionID: String,
        model: RuntimeServices.Model,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        recording: RuntimeServices.Recording = .init()
    ) async throws -> AgentRunner.Result {
        let session = try await begin(
            agent,
            from: parentSessionID,
            sessionID: sessionID
        )
        guard var entry = entries[session.id] else {
            throw Failure.unknownSession(session.id)
        }
        entry.runner = runtime.makeAgentRunner(
            realization: entry.realization,
            capabilityState: entry.capabilities,
            model: model,
            configuration: configuration,
            tooling: tooling,
            recording: recording
        )
        entries[session.id] = entry
        return try await perform(session.id) { runner in
            try await runner.run(request, sessionID: session.id)
        }
    }

    /// Continue the same admitted child runner rather than starting another
    /// root Agent. The runner owns its checkpoint restoration semantics.
    public func resume(_ sessionID: String) async throws -> AgentRunner.Result {
        try await perform(sessionID) { runner in
            try await runner.resume(sessionID: sessionID)
        }
    }

    public func resume(
        _ sessionID: String,
        reply: UserInputReply,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunner.Result {
        try await perform(sessionID) { runner in
            try await runner.resume(
                sessionID: sessionID,
                reply: reply,
                metadata: metadata
            )
        }
    }

    /// Never allow concurrent calls to execute the same admitted session.
    /// A thrown runner error retains the reservation, since its checkpoint
    /// may still require repair or resumption. No implicit root retry occurs.
    private func perform(
        _ sessionID: String,
        operation: @Sendable (AgentRunner) async throws -> AgentRunner.Result
    ) async throws -> AgentRunner.Result {
        guard var entry = entries[sessionID] else {
            throw Failure.unknownSession(sessionID)
        }
        guard !entry.settled else {
            throw Failure.settledSession(sessionID)
        }
        guard !entry.executing else {
            throw Failure.executionInProgress(sessionID)
        }
        guard let runner = entry.runner else {
            throw Failure.executionNotStarted(sessionID)
        }
        entry.executing = true
        entries[sessionID] = entry
        do {
            let result = try await operation(runner)
            guard result.sessionID == sessionID else {
                throw Failure.resultIdentityMismatch(
                    expected: sessionID,
                    actual: result.sessionID
                )
            }
            guard var current = entries[sessionID] else {
                throw Failure.unknownSession(sessionID)
            }
            current.executing = false
            entries[sessionID] = current
            if result.isCompleted || result.isFailed {
                try settle(result)
            }
            return result
        } catch {
            if var current = entries[sessionID] {
                current.executing = false
                entries[sessionID] = current
            }
            throw error
        }
    }

    private func lineage(from id: String) throws -> [Entry] {
        var result: [Entry] = []
        var current: String? = id
        while let identifier = current {
            guard let entry = entries[identifier] else {
                throw Failure.unknownSession(identifier)
            }
            result.append(entry)
            current = entry.session.parentSessionID
        }
        return result
    }

    private func isDescendant(_ candidate: Session, of ancestorID: String) -> Bool {
        var current = candidate.parentSessionID
        while let identifier = current {
            if identifier == ancestorID { return true }
            current = entries[identifier]?.session.parentSessionID
        }
        return false
    }
}
