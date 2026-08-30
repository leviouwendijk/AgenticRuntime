import Agentic
import AgenticExecution
import Foundation

public enum AgentToolPlanRunCoordinatorError:
    Error,
    Sendable,
    LocalizedError,
    Equatable
{
    case duplicateRunID(String)
    case missingRun(String)
    case runBusy(String)
    case staleRevision(
        runID: String,
        expected: Int,
        actual: Int
    )
    case recoveryParentNotSuspended(String)
    case recoveryParentAlreadyResolved(String)
    case activeRecoveryChild(parentRunID: String, childRunID: String)
    case maximumRecoveryDepthExceeded(parentRunID: String, maximumDepth: Int)

    public var errorDescription: String? {
        switch self {
        case .duplicateRunID(let runID):
            return "AgentToolPlanRun '\(runID)' already exists in this runtime coordinator."

        case .missingRun(let runID):
            return "No live AgentToolPlanRun exists for id '\(runID)'."

        case .runBusy(let runID):
            return "AgentToolPlanRun '\(runID)' already has an execution control in flight."

        case .staleRevision(
            let runID,
            let expected,
            let actual
        ):
            return "AgentToolPlanRun '\(runID)' revision is \(actual), not expected revision \(expected)."

        case .recoveryParentNotSuspended(let runID):
            return "AgentToolPlanRun '\(runID)' is not suspended at a recoverable failure."

        case .recoveryParentAlreadyResolved(let runID):
            return "AgentToolPlanRun '\(runID)' has already resolved its interruption and is awaiting continuation."

        case .activeRecoveryChild(let parentRunID, let childRunID):
            return "AgentToolPlanRun '\(parentRunID)' has active recovery child '\(childRunID)' for its current suspension."

        case .maximumRecoveryDepthExceeded(let parentRunID, let maximumDepth):
            return "AgentToolPlanRun '\(parentRunID)' cannot create another recovery because the maximum recovery depth is \(maximumDepth)."
        }
    }
}

/// Process-local owner for live resumable tool-plan runs.
///
/// This deliberately has no persistence contract. A longer-lived Runtime host
/// may retain one coordinator for as long as its interactive/session process is
/// alive. Durable restoration can be designed later without changing the
/// execution semantics represented by AgentToolPlanRun.
public actor AgentToolPlanRunCoordinator {
    public let executor: AgentToolPlanRunExecutor
    public let context: AgentToolExecutionContext
    public let approvalHandler: (any ToolApprovalHandler)?
    public let maximumRecoveryDepth: Int

    private var runsByID: [String: AgentToolPlanRun] = [:]
    private var runOrder: [String] = []
    private var busyRunIDs: Set<String> = []
    private var recoveryParentRevisionsByRunID: [String: Int] = [:]

    public init(
        invoker: ToolInvoker,
        context: AgentToolExecutionContext = .init(),
        approvalHandler: (any ToolApprovalHandler)? = nil,
        maximumRecoveryDepth: Int = 4
    ) {
        self.executor = AgentToolPlanRunExecutor(
            invoker: invoker
        )
        self.context = context
        self.approvalHandler = approvalHandler
        self.maximumRecoveryDepth = max(0, maximumRecoveryDepth)
    }

    public func start(
        _ plan: AgentToolPlan,
        runID: String = UUID().uuidString
    ) async throws -> AgentToolPlanRun {
        try reserveNewRun(
            runID
        )
        defer {
            busyRunIDs.remove(
                runID
            )
        }

        let run = try await executor.start(
            plan,
            runID: runID,
            relationship: .root,
            context: context,
            approvalHandler: approvalHandler
        )

        storeNew(
            run
        )

        return run
    }

    /// Execute a child recovery plan while leaving its parent untouched.
    ///
    /// Recovery plans are ordinary AgentToolPlan runs. If a recovery plan
    /// suspends, it can itself become the parent of another recovery plan.
    /// Successful recovery does not imply that the failed parent node should be
    /// retried or skipped; that remains an explicit caller decision.
    public func recover(
        parentRunID: String,
        expectedParentRevision: Int,
        plan: AgentToolPlan,
        runID: String = UUID().uuidString
    ) async throws -> AgentToolPlanRun {
        let parent = try currentRun(
            id: parentRunID,
            expectedRevision: expectedParentRevision
        )

        try requireRecoverableParent(
            parent
        )
        try requireNoActiveRecovery(for: parent)
        try requireRecoveryDepthAvailable(for: parent)

        try reserveExistingRun(
            parentRunID
        )

        do {
            try reserveNewRun(
                runID
            )
        } catch {
            busyRunIDs.remove(
                parentRunID
            )
            throw error
        }

        defer {
            busyRunIDs.remove(
                parentRunID
            )
            busyRunIDs.remove(
                runID
            )
        }

        let recovery = try await executor.start(
            plan,
            runID: runID,
            relationship: .recovery(
                parentRunID: parentRunID
            ),
            context: context,
            approvalHandler: approvalHandler
        )

        storeNew(
            recovery
        )
        recoveryParentRevisionsByRunID[recovery.id] = parent.revision

        return recovery
    }

    public func run(
        id: String
    ) throws -> AgentToolPlanRun {
        guard let run = runsByID[id] else {
            throw AgentToolPlanRunCoordinatorError.missingRun(
                id
            )
        }

        return run
    }

    public func runs() -> [AgentToolPlanRun] {
        runOrder.compactMap { runID in
            runsByID[runID]
        }
    }

    public func recoveries(
        of parentRunID: String
    ) -> [AgentToolPlanRun] {
        runs().filter { run in
            guard case .recovery(
                parentRunID: let candidateParentRunID
            ) = run.relationship else {
                return false
            }

            return candidateParentRunID == parentRunID
        }
    }

    public func recoveryDepth(
        of runID: String
    ) throws -> Int {
        var depth = 0
        var candidate = try requiredRun(id: runID)

        while case .recovery(parentRunID: let parentRunID) = candidate.relationship {
            depth += 1
            candidate = try requiredRun(id: parentRunID)
        }

        return depth
    }

    public func activeRecovery(
        of parentRunID: String
    ) throws -> AgentToolPlanRun? {
        activeRecovery(for: try requiredRun(id: parentRunID))
    }

    public func isBusy(
        runID: String
    ) -> Bool {
        busyRunIDs.contains(
            runID
        )
    }

    public func retry(
        runID: String,
        expectedRevision: Int
    ) async throws -> AgentToolPlanRun {
        let run = try currentRun(
            id: runID,
            expectedRevision: expectedRevision
        )

        try requireNoActiveRecovery(for: run)
        try reserveExistingRun(
            runID
        )
        defer {
            busyRunIDs.remove(
                runID
            )
        }

        let updated = try await executor.retry(
            run,
            context: context,
            approvalHandler: approvalHandler
        )

        replace(
            updated
        )

        return updated
    }

    public func skip(
        runID: String,
        expectedRevision: Int
    ) throws -> AgentToolPlanRun {
        let run = try currentRun(
            id: runID,
            expectedRevision: expectedRevision
        )

        try requireNoActiveRecovery(for: run)

        guard !busyRunIDs.contains(runID) else {
            throw AgentToolPlanRunCoordinatorError.runBusy(
                runID
            )
        }

        let updated = try executor.skip(
            run
        )

        replace(
            updated
        )

        return updated
    }

    public func resume(
        runID: String,
        expectedRevision: Int
    ) async throws -> AgentToolPlanRun {
        let run = try currentRun(
            id: runID,
            expectedRevision: expectedRevision
        )

        try reserveExistingRun(
            runID
        )
        defer {
            busyRunIDs.remove(
                runID
            )
        }

        try requireNoActiveRecovery(for: run)

        let updated = try await executor.resume(
            run,
            context: context,
            approvalHandler: approvalHandler
        )

        replace(
            updated
        )

        return updated
    }
}

private extension AgentToolPlanRunCoordinator {
    func requiredRun(id: String) throws -> AgentToolPlanRun {
        guard let run = runsByID[id] else {
            throw AgentToolPlanRunCoordinatorError.missingRun(id)
        }
        return run
    }

    func currentRun(
        id: String,
        expectedRevision: Int
    ) throws -> AgentToolPlanRun {
        let run = try requiredRun(id: id)

        guard run.revision == expectedRevision else {
            throw AgentToolPlanRunCoordinatorError.staleRevision(
                runID: id,
                expected: expectedRevision,
                actual: run.revision
            )
        }

        return run
    }

    func activeRecovery(for parent: AgentToolPlanRun) -> AgentToolPlanRun? {
        for runID in runOrder.reversed() {
            guard recoveryParentRevisionsByRunID[runID] == parent.revision,
                  let run = runsByID[runID],
                  case .recovery(
                    parentRunID: let candidateParentRunID
                  ) = run.relationship,
                  candidateParentRunID == parent.id,
                  !isTerminal(run)
            else {
                continue
            }
            return run
        }
        return nil
    }

    func requireNoActiveRecovery(for parent: AgentToolPlanRun) throws {
        guard let child = activeRecovery(for: parent) else { return }
        throw AgentToolPlanRunCoordinatorError.activeRecoveryChild(
            parentRunID: parent.id,
            childRunID: child.id
        )
    }

    func requireRecoveryDepthAvailable(for parent: AgentToolPlanRun) throws {
        guard try recoveryDepth(of: parent.id) + 1 <= maximumRecoveryDepth else {
            throw AgentToolPlanRunCoordinatorError.maximumRecoveryDepthExceeded(
                parentRunID: parent.id,
                maximumDepth: maximumRecoveryDepth
            )
        }
    }

    func isTerminal(_ run: AgentToolPlanRun) -> Bool {
        switch run.state {
        case .completed, .stopped:
            return true
        case .suspended:
            return false
        }
    }

    func requireRecoverableParent(
        _ parent: AgentToolPlanRun
    ) throws {
        guard case .suspended(let suspension) = parent.state else {
            throw AgentToolPlanRunCoordinatorError
                .recoveryParentNotSuspended(
                    parent.id
                )
        }

        switch suspension.reason {
        case .failure:
            return

        case .continuation_required:
            throw AgentToolPlanRunCoordinatorError
                .recoveryParentAlreadyResolved(
                    parent.id
                )

        case .human_review:
            throw AgentToolPlanRunCoordinatorError
                .recoveryParentNotSuspended(
                    parent.id
                )
        }
    }

    func reserveNewRun(
        _ runID: String
    ) throws {
        guard runsByID[runID] == nil,
              !busyRunIDs.contains(runID)
        else {
            throw AgentToolPlanRunCoordinatorError.duplicateRunID(
                runID
            )
        }

        busyRunIDs.insert(
            runID
        )
    }

    func reserveExistingRun(
        _ runID: String
    ) throws {
        guard !busyRunIDs.contains(runID) else {
            throw AgentToolPlanRunCoordinatorError.runBusy(
                runID
            )
        }

        busyRunIDs.insert(
            runID
        )
    }

    func storeNew(
        _ run: AgentToolPlanRun
    ) {
        runsByID[run.id] = run
        runOrder.append(
            run.id
        )
    }

    func replace(
        _ run: AgentToolPlanRun
    ) {
        runsByID[run.id] = run
    }
}
