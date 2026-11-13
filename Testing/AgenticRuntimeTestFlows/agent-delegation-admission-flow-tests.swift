import Agentic
import AgenticRuntime
import TestFlows

private enum DelegationRootFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose = "Delegation admission root."
    static let identifier = AgentIdentifier(rawValue: "fixture.delegation.root")
    static let capabilities = AgentCapabilities(
        available: .init(agents: .init(members: [
            DelegationIntermediateFixture.identifier,
            DelegationLeafFixture.identifier,
            DelegationExcludedFixture.identifier
        ]))
    )
    static let delegation = AgentDelegationPolicy.bounded(
        allowedAgents: .init(members: [
            DelegationIntermediateFixture.identifier,
            DelegationLeafFixture.identifier
        ]),
        limits: .init(depth: 2, children: 2, descendants: 3, concurrentChildren: 1)
    )
    static let definition = AgentDefinition(
        identifier: identifier,
        purpose: purpose,
        capabilities: capabilities,
        delegation: delegation
    )
}

private enum DelegationIntermediateFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose = "Delegation admission intermediate."
    static let identifier = AgentIdentifier(rawValue: "fixture.delegation.intermediate")
    static let capabilities = AgentCapabilities(
        available: .init(agents: .init(members: [
            DelegationLeafFixture.identifier,
            DelegationRootFixture.identifier
        ]))
    )
    static let delegation = AgentDelegationPolicy.bounded(
        allowedAgents: .init(members: [
            DelegationLeafFixture.identifier,
            DelegationRootFixture.identifier
        ]),
        limits: .init(depth: 1, children: 2, descendants: 2, concurrentChildren: 1)
    )
    static let definition = AgentDefinition(
        identifier: identifier,
        purpose: purpose,
        capabilities: capabilities,
        delegation: delegation
    )
}

private enum DelegationLeafFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose = "Delegation admission terminal leaf."
    static let identifier = AgentIdentifier(rawValue: "fixture.delegation.leaf")
    static let definition = AgentDefinition(identifier: identifier, purpose: purpose)
}

private enum DelegationExcludedFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose = "Installed, available, but not delegated."
    static let identifier = AgentIdentifier(rawValue: "fixture.delegation.excluded")
    static let definition = AgentDefinition(identifier: identifier, purpose: purpose)
}

private enum DelegationShallowRootFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose = "Delegation depth-limited root."
    static let identifier = AgentIdentifier(rawValue: "fixture.delegation.shallow")
    static let capabilities = AgentCapabilities(
        available: .init(agents: .init(members: [DelegationIntermediateFixture.identifier]))
    )
    static let delegation = AgentDelegationPolicy.bounded(
        allowedAgents: .init(members: [DelegationIntermediateFixture.identifier]),
        limits: .init(depth: 1, children: 2, descendants: 3, concurrentChildren: 1)
    )
    static let definition = AgentDefinition(
        identifier: identifier,
        purpose: purpose,
        capabilities: capabilities,
        delegation: delegation
    )
}

private enum DelegationChildLimitedRootFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose = "Delegation child-count-limited root."
    static let identifier = AgentIdentifier(rawValue: "fixture.delegation.child_limited")
    static let capabilities = AgentCapabilities(
        available: .init(agents: .init(members: [
            DelegationIntermediateFixture.identifier, DelegationLeafFixture.identifier
        ]))
    )
    static let delegation = AgentDelegationPolicy.bounded(
        allowedAgents: .init(members: [
            DelegationIntermediateFixture.identifier, DelegationLeafFixture.identifier
        ]),
        limits: .init(depth: 2, children: 1, descendants: 3, concurrentChildren: 1)
    )
    static let definition = AgentDefinition(
        identifier: identifier,
        purpose: purpose,
        capabilities: capabilities,
        delegation: delegation
    )
}

private enum DelegationReentrantRootFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose = "Delegation policy allowing bounded definition reentry."
    static let identifier = AgentIdentifier(rawValue: "fixture.delegation.reentrant")
    static let capabilities = AgentCapabilities(
        available: .init(agents: .init(members: [identifier]))
    )
    static let delegation = AgentDelegationPolicy.bounded(
        allowedAgents: .init(members: [identifier]),
        limits: .init(depth: 2, children: 2, descendants: 2, concurrentChildren: 1),
        reentry: .allow_same_definition(maxOccurrences: 2)
    )
    static let definition = AgentDefinition(
        identifier: identifier,
        purpose: purpose,
        capabilities: capabilities,
        delegation: delegation
    )
}

private func terminalDelegationResult(_ sessionID: String) -> AgentRunner.Result {
    .completed(
        sessionID: sessionID,
        response: AgentResponse(
            message: Message(role: .assistant, text: "finished"),
            stopReason: .end_turn
        ),
        state: .init()
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runAgentDelegationAdmission() async throws -> [TestDiagnostic] {
        let application = Agentic.application("fixture.delegation.admission") {
            install(DelegationRootFixture.self)
            install(DelegationIntermediateFixture.self)
            install(DelegationLeafFixture.self)
            install(DelegationExcludedFixture.self)
            install(DelegationShallowRootFixture.self)
            install(DelegationChildLimitedRootFixture.self)
            install(DelegationReentrantRootFixture.self)
        }
        let runtime = try await AgenticRuntime(application: application)
        let root_state = try runtime.realizeAgent(
            identifiedBy: DelegationRootFixture.identifier
        ).makeCapabilityState()
        let admission = try AgentDelegation(
            runtime: runtime,
            root: DelegationRootFixture.identifier,
            sessionID: "root-session",
            capabilityState: root_state
        )

        var denied_unlisted = false
        do {
            _ = try await admission.begin(
                DelegationExcludedFixture.identifier,
                from: "root-session",
                sessionID: "rejected-unlisted"
            )
        } catch AgentDelegation.Failure.notAllowed {
            denied_unlisted = true
        }
        try Expect.true(denied_unlisted, "Policy selection must bind delegated identities")

        let intermediate = try await admission.begin(
            DelegationIntermediateFixture.identifier,
            from: "root-session",
            sessionID: "middle-session"
        )
        try Expect.equal(intermediate.parentSessionID, "root-session", "Child lineage")
        try Expect.equal(intermediate.depth, 1, "First-level depth")

        var denied_concurrent = false
        do {
            _ = try await admission.begin(
                DelegationLeafFixture.identifier,
                from: "root-session",
                sessionID: "premature-sibling"
            )
        } catch AgentDelegation.Failure.concurrencyLimitExceeded {
            denied_concurrent = true
        }
        try Expect.true(denied_concurrent, "Unsettled direct children occupy concurrency")

        var denied_duplicate = false
        do {
            _ = try await admission.begin(
                DelegationLeafFixture.identifier,
                from: "middle-session",
                sessionID: "middle-session"
            )
        } catch AgentDelegation.Failure.duplicateSession {
            denied_duplicate = true
        }
        try Expect.true(denied_duplicate, "Session identity must remain unique")

        var denied_reentry = false
        do {
            _ = try await admission.begin(
                DelegationRootFixture.identifier,
                from: "middle-session",
                sessionID: "cycle-session"
            )
        } catch AgentDelegation.Failure.reentry {
            denied_reentry = true
        }
        try Expect.true(denied_reentry, "Ancestor-definition reentry fails closed")

        let leaf = try await admission.begin(
            DelegationLeafFixture.identifier,
            from: "middle-session",
            sessionID: "grandchild-session"
        )
        try Expect.equal(leaf.depth, 2, "Nested depth")
        try Expect.equal(leaf.parentSessionID, "middle-session", "Grandchild lineage")

        var denied_unsettled = false
        do {
            try await admission.settle(terminalDelegationResult("middle-session"))
        } catch AgentDelegation.Failure.activeDescendants {
            denied_unsettled = true
        }
        try Expect.true(denied_unsettled, "Parents must retain active descendants")

        var denied_nonterminal = false
        do {
            try await admission.settle(AgentRunner.Result(
                sessionID: "grandchild-session",
                phase: .suspended,
                response: nil,
                state: .init()
            ))
        } catch AgentDelegation.Failure.nonterminalResult {
            denied_nonterminal = true
        }
        try Expect.true(denied_nonterminal, "Suspended children retain reservations")

        try await admission.settle(terminalDelegationResult("grandchild-session"))
        try await admission.settle(terminalDelegationResult("middle-session"))

        _ = await root_state.disable(.init(agents: [DelegationLeafFixture.identifier]))
        var denied_revoked = false
        do {
            _ = try await admission.begin(
                DelegationLeafFixture.identifier,
                from: "root-session",
                sessionID: "revoked-session"
            )
        } catch AgentDelegation.Failure.notAvailable {
            denied_revoked = true
        }
        try Expect.true(denied_revoked, "Live root capability revocation blocks admission")
        _ = try await root_state.enable(.init(agents: [DelegationLeafFixture.identifier]))

        _ = try await admission.begin(
            DelegationLeafFixture.identifier,
            from: "root-session",
            sessionID: "sibling-session"
        )
        var denied_descendants = false
        do {
            _ = try await admission.begin(
                DelegationLeafFixture.identifier,
                from: "root-session",
                sessionID: "excess-descendant"
            )
        } catch AgentDelegation.Failure.descendantLimitExceeded {
            denied_descendants = true
        }
        try Expect.true(denied_descendants, "Ancestor descendant cap survives settlement")
        try await admission.settle(terminalDelegationResult("sibling-session"))
        try await admission.settle(terminalDelegationResult("root-session"))

        var denied_settled = false
        do {
            _ = try await admission.begin(
                DelegationLeafFixture.identifier,
                from: "root-session",
                sessionID: "after-settlement"
            )
        } catch AgentDelegation.Failure.settledSession {
            denied_settled = true
        }
        try Expect.true(denied_settled, "Settled parents cannot delegate again")

        let disabled = try AgentDelegation(
            runtime: runtime,
            root: DelegationLeafFixture.identifier,
            sessionID: "disabled-root",
            capabilityState: try runtime.realizeAgent(
                identifiedBy: DelegationLeafFixture.identifier
            ).makeCapabilityState()
        )
        var denied_disabled = false
        do {
            _ = try await disabled.begin(
                DelegationRootFixture.identifier,
                from: "disabled-root",
                sessionID: "not-authorized"
            )
        } catch AgentDelegation.Failure.disabled {
            denied_disabled = true
        }
        try Expect.true(denied_disabled, "Delegation defaults disabled")
        let shallow = try AgentDelegation(
            runtime: runtime,
            root: DelegationShallowRootFixture.identifier,
            sessionID: "shallow-root",
            capabilityState: try runtime.realizeAgent(
                identifiedBy: DelegationShallowRootFixture.identifier
            ).makeCapabilityState()
        )
        _ = try await shallow.begin(
            DelegationIntermediateFixture.identifier,
            from: "shallow-root",
            sessionID: "shallow-child"
        )
        var denied_depth = false
        do {
            _ = try await shallow.begin(
                DelegationLeafFixture.identifier,
                from: "shallow-child",
                sessionID: "too-deep"
            )
        } catch AgentDelegation.Failure.depthExceeded {
            denied_depth = true
        }
        try Expect.true(denied_depth, "Root depth budget binds every descendant")

        let child_limited = try AgentDelegation(
            runtime: runtime,
            root: DelegationChildLimitedRootFixture.identifier,
            sessionID: "child-limited-root",
            capabilityState: try runtime.realizeAgent(
                identifiedBy: DelegationChildLimitedRootFixture.identifier
            ).makeCapabilityState()
        )
        _ = try await child_limited.begin(
            DelegationIntermediateFixture.identifier,
            from: "child-limited-root",
            sessionID: "first-child"
        )
        try await child_limited.settle(terminalDelegationResult("first-child"))
        var denied_children = false
        do {
            _ = try await child_limited.begin(
                DelegationLeafFixture.identifier,
                from: "child-limited-root",
                sessionID: "second-child"
            )
        } catch AgentDelegation.Failure.childLimitExceeded {
            denied_children = true
        }
        try Expect.true(denied_children, "Total direct child budget survives settlement")

        let reentry = try AgentDelegation(
            runtime: runtime,
            root: DelegationReentrantRootFixture.identifier,
            sessionID: "reentry-root",
            capabilityState: try runtime.realizeAgent(
                identifiedBy: DelegationReentrantRootFixture.identifier
            ).makeCapabilityState()
        )
        _ = try await reentry.begin(
            DelegationReentrantRootFixture.identifier,
            from: "reentry-root",
            sessionID: "reentry-once"
        )
        var denied_reentry_limit = false
        do {
            _ = try await reentry.begin(
                DelegationReentrantRootFixture.identifier,
                from: "reentry-once",
                sessionID: "reentry-twice"
            )
        } catch AgentDelegation.Failure.reentry {
            denied_reentry_limit = true
        }
        try Expect.true(denied_reentry_limit, "Bounded same-definition reentry is enforced")

        return []
    }
}

private actor DelegatedCheckpointStore: AgentHistoryStore {
    private var values: [String: AgentRunner.Checkpoint] = [:]

    func loadCheckpoint(sessionID: String) async throws -> AgentRunner.Checkpoint? {
        values[sessionID]
    }

    func saveCheckpoint(_ checkpoint: AgentRunner.Checkpoint) async throws {
        values[checkpoint.id] = checkpoint
    }

    func deleteCheckpoint(sessionID: String) async throws {
        values.removeValue(forKey: sessionID)
    }
}

private actor DelegatedExecutionRecorder {
    private var invocations: [AgentModelInvocation] = []

    func append(_ invocation: AgentModelInvocation) {
        invocations.append(invocation)
    }

    func snapshot() -> [AgentModelInvocation] { invocations }
}

private struct DelegatedExecutionModel: AgentModelInvoking {
    let recorder: DelegatedExecutionRecorder

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocation.Result {
        await recorder.append(invocation)
        return result(for: invocation)
    }

    func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<AgentModelInvocation.Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await recorder.append(invocation)
                continuation.yield(.completed(result(for: invocation)))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func result(
        for invocation: AgentModelInvocation
    ) -> AgentModelInvocation.Result {
        let response = AgentResponse(
            message: Message(role: .assistant, text: "delegated child completed"),
            stopReason: .end_turn
        )
        let profile = AgentModelProfile(
            identifier: "fixture.delegation.profile",
            gatewayIdentifier: "fixture.delegation.gateway",
            model: "fixture-model",
            purposes: [invocation.selection.purpose],
            capabilities: [.text, .reasoning, .structured_output]
        )
        let route = AgentModelRoute(
            purpose: invocation.selection.purpose,
            profile: profile
        )
        return AgentModelInvocation.Result(
            response: response,
            route: AgentModelRouteRecord(
                route: route,
                requestMetadata: invocation.metadata,
                responseMetadata: response.metadata,
                usage: response.usage
            )
        )
    }
}

private actor DelegatedTextRouteRecorder {
    private var invocations: [AgentModelInvocation] = []

    func append(_ invocation: AgentModelInvocation) -> Int {
        let index = invocations.count
        invocations.append(invocation)
        return index
    }

    func snapshot() -> [AgentModelInvocation] {
        invocations
    }
}

private struct DelegatedTextRouteInvoker: AgentModelInvoking {
    let recorder: DelegatedTextRouteRecorder
    let function: String

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocation.Result {
        let index = await recorder.append(invocation)
        let response: AgentResponse

        if invocation.request.metadata["parent_agent_session_id"] != nil {
            response = AgentResponse(
                message: Message(role: .assistant, text: "child-text-response"),
                stopReason: .end_turn
            )
        } else if index == 0 {
            response = AgentResponse(
                message: Message(
                    role: .assistant,
                    content: MessageContent(blocks: [
                        .tool_call(ToolCall(
                            id: "delegation-text-call",
                            tool: ToolIdentifier(rawValue: function),
                            input: .object([
                                "arguments": .string("Perform the bounded task")
                            ])
                        ))
                    ])
                ),
                stopReason: .tool_use
            )
        } else {
            response = AgentResponse(
                message: Message(role: .assistant, text: "parent-completed"),
                stopReason: .end_turn
            )
        }

        let route = AgentModelRoute(
            purpose: invocation.selection.purpose,
            profile: AgentModelProfile(
                identifier: "fixture.delegation.text_profile",
                gatewayIdentifier: "fixture.delegation.text_gateway",
                model: "fixture",
                purposes: [invocation.selection.purpose],
                capabilities: [.text, .tool_use, .streaming]
            )
        )
        return AgentModelInvocation.Result(
            response: response,
            route: AgentModelRouteRecord(
                route: route,
                requestMetadata: invocation.request.metadata,
                responseMetadata: response.metadata,
                usage: response.usage
            )
        )
    }

    func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<AgentModelInvocation.Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.completed(try await buffered(invocation)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private enum DelegationPreferredSelectionFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose = "Delegation model preference override fixture."
    static let identifier = AgentIdentifier(
        rawValue: "fixture.delegation.preferred_selection"
    )
    static let modelSelection = AgentModelSelection(
        purpose: .coder,
        preferences: .init(
            preferredModelID: "fixture.worker.model",
            gateway: "fixture.worker.gateway"
        )
    )
    static let definition = AgentDefinition(
        identifier: identifier,
        purpose: purpose,
        modelSelection: modelSelection
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runAgentDelegationExecution() async throws -> [TestDiagnostic] {
        let application = Agentic.application("fixture.delegation.execution") {
            install(DelegationRootFixture.self)
            install(DelegationIntermediateFixture.self)
            install(DelegationLeafFixture.self)
            install(DelegationExcludedFixture.self)
            install(DelegationPreferredSelectionFixture.self)
        }
        let runtime = try await AgenticRuntime(application: application)
        let root = try runtime.makeAgentRunner(
            identifiedBy: DelegationRootFixture.identifier,
            model: .init(invoker: DelegatedExecutionModel(recorder: .init()))
        )
        let root_state = await root.capabilityState
        let admission = try AgentDelegation(
            runtime: runtime,
            root: DelegationRootFixture.identifier,
            sessionID: "real-parent",
            capabilityState: root_state
        )
        let recorder = DelegatedExecutionRecorder()
        let model = RuntimeServices.Model(
            invoker: DelegatedExecutionModel(recorder: recorder),
            selection: .init(
                purpose: .executor,
                preferences: .init(
                    preferredModelID: "fixture.application.model",
                    gateway: "fixture.application.gateway"
                ),
                constraints: .init(allowsExternal: false)
            )
        )
        let child = try await admission.run(
            DelegationLeafFixture.identifier,
            request: .init(messages: [Message(role: .user, text: "execute as child")]),
            from: "real-parent",
            sessionID: "real-child",
            model: model
        )
        try Expect.true(child.isCompleted, "Governed child executes to completion")
        try Expect.equal(child.sessionID, "real-child", "Reserved child identity reaches AgentRunner")
        try Expect.equal(
            child.response?.message.content.text,
            "delegated child completed",
            "Child result returns from governed runner"
        )
        let calls = await recorder.snapshot()
        try Expect.equal(calls.count, 1, "Delegation executes exactly one model invocation")
        try Expect.equal(
            calls.first?.selection.preferences.preferredModelID?.rawValue,
            "fixture.application.model",
            "Unconfigured delegated Agent inherits the caller's resolved model"
        )
        try Expect.equal(
            calls.first?.selection.preferences.gateway?.rawValue,
            "fixture.application.gateway",
            "Unconfigured delegated Agent inherits the caller's gateway"
        )
        try Expect.true(
            calls.first?.selection.constraints.allowsExternal == false,
            "Delegation retains inherited hard model restrictions"
        )
        try Expect.equal(
            calls.first?.request.tools.count,
            0,
            "Child model projection respects its own authored visibility"
        )
        let lineage = await admission.session("real-child")
        try Expect.equal(lineage?.parentSessionID, "real-parent", "Executed child keeps parent lineage")

        let preferredRunner = try runtime.makeAgentRunner(
            identifiedBy: DelegationPreferredSelectionFixture.identifier,
            model: model
        )
        let preferredSelection = await preferredRunner.model.selection
        try Expect.equal(
            preferredSelection.purpose, .coder,
            "Child keeps its own authored model purpose"
        )
        try Expect.equal(
            preferredSelection.preferences.preferredModelID?.rawValue,
            "fixture.worker.model",
            "Explicit Agent preference overrides an inherited default"
        )
        try Expect.equal(
            preferredSelection.preferences.gateway?.rawValue,
            "fixture.worker.gateway",
            "Explicit Agent gateway overrides an inherited default"
        )
        try Expect.true(
            !preferredSelection.constraints.allowsExternal,
            "Agent override cannot weaken inherited hard restrictions"
        )

        let explicitRunner = try runtime.makeAgentRunner(
            identifiedBy: DelegationPreferredSelectionFixture.identifier,
            model: model,
            modelPreferences: .init(
                preferredModelID: "fixture.invocation.model",
                gateway: "fixture.invocation.gateway"
            )
        )
        let explicitSelection = await explicitRunner.model.selection
        try Expect.equal(
            explicitSelection.preferences.preferredModelID?.rawValue,
            "fixture.invocation.model",
            "Explicit runtime preference overrides the Agent preference"
        )
        try Expect.equal(
            explicitSelection.preferences.gateway?.rawValue,
            "fixture.invocation.gateway",
            "Explicit runtime gateway overrides the Agent preference"
        )
        try Expect.true(
            !explicitSelection.constraints.allowsExternal,
            "Explicit preferences cannot relax a hard inherited restriction"
        )

        var denied_duplicate = false
        do {
            _ = try await admission.run(
                DelegationLeafFixture.identifier,
                request: .init(messages: []),
                from: "real-parent",
                sessionID: "real-child",
                model: model
            )
        } catch AgentDelegation.Failure.duplicateSession {
            denied_duplicate = true
        }
        try Expect.true(denied_duplicate, "Executed child cannot be launched twice")

        var denied_resumption = false
        do {
            _ = try await admission.resume("real-child")
        } catch AgentDelegation.Failure.settledSession {
            denied_resumption = true
        }
        try Expect.true(denied_resumption, "Terminal child cannot resume")

        var denied_no_runner = false
        _ = try await admission.begin(
            DelegationIntermediateFixture.identifier,
            from: "real-parent",
            sessionID: "admitted-only"
        )
        do {
            _ = try await admission.resume("admitted-only")
        } catch AgentDelegation.Failure.executionNotStarted {
            denied_no_runner = true
        }
        try Expect.true(denied_no_runner, "Admission alone cannot invent a runner")

        // Model projection is an actual Agent capability call, not a second Tool.
        // The identity and delegation tree are Host-created, never model arguments.
        let modelState = try runtime.realizeAgent(
            identifiedBy: DelegationRootFixture.identifier
        ).makeCapabilityState()
        _ = await modelState.reveal(.init(agents: [DelegationLeafFixture.identifier]))
        let modelDelegation = try AgentDelegation(
            runtime: runtime,
            root: DelegationRootFixture.identifier,
            sessionID: "model-parent",
            capabilityState: modelState
        )
        let inventory = CapabilityInventory(installed: runtime.installed, state: modelState)
        let projection = try await inventory.modelProjection()
        let agentTarget = CapabilityInvocation.Target.agent(DelegationLeafFixture.identifier)
        let function = try Expect.notNil(
            projection.name(for: agentTarget),
            "Visible Agent capabilities are model-callable"
        )
        let dispatcher = CapabilityDispatcher(
            inventory: inventory,
            services: .init(model: model),
            delegation: modelDelegation,
            parentSessionID: "model-parent"
        )
        let delegated = try await dispatcher.invoke(
            .agent(
                identifier: DelegationLeafFixture.identifier,
                request: .init(messages: [Message(role: .user, text: "delegated work")]),
                sessionID: "model-child"
            ),
            origin: .model(projection: projection, function: function)
        )
        guard case .agent(let completed) = delegated else {
            throw CapabilityInvocationError.agentRequiresDelegation(
                DelegationLeafFixture.identifier
            )
        }
        try Expect.true(completed.isCompleted, "Model Agent capability executes as child")
        try Expect.equal(completed.sessionID, "model-child", "Child identity is preserved")
        let modelLineage = await modelDelegation.session("model-child")
        try Expect.equal(modelLineage?.parentSessionID, "model-parent", "Parent lineage is governed")

        // Exercise the actual model-originated Agent Tool path. A String-returning
        // worker must not require structured_output or JSON parsing of plain text.
        let textState = try runtime.realizeAgent(
            identifiedBy: DelegationRootFixture.identifier
        ).makeCapabilityState()
        _ = await textState.reveal(.init(agents: [DelegationLeafFixture.identifier]))
        let textInventory = CapabilityInventory(installed: runtime.installed, state: textState)
        let textProjection = try await textInventory.modelProjection()
        let textFunction = try Expect.notNil(
            textProjection.name(for: .agent(DelegationLeafFixture.identifier)),
            "Delegated text worker is projected as a model-callable Agent"
        )
        let textDelegation = try AgentDelegation(
            runtime: runtime,
            root: DelegationRootFixture.identifier,
            sessionID: "text-parent",
            capabilityState: textState
        )
        let textRecorder = DelegatedTextRouteRecorder()
        let textInvoker = DelegatedTextRouteInvoker(
            recorder: textRecorder,
            function: textFunction
        )
        let textRunner = AgentRunner(
            model: .init(invoker: textInvoker, selection: model.selection),
            inventory: textInventory,
            delegation: textDelegation
        )
        let textResult = try await textRunner.run(
            .init(messages: [Message(role: .user, text: "Delegate a text task")]),
            sessionID: "text-parent"
        )
        try Expect.true(textResult.isCompleted, "Text worker completes through model delegation")
        let textCalls = await textRecorder.snapshot()
        try Expect.equal(textCalls.count, 3, "Parent, child, parent use three model calls")
        let childCall = try Expect.notNil(
            textCalls.first(where: { $0.request.metadata["parent_agent_session_id"] != nil }),
            "One model invocation belongs to the delegated child"
        )
        try Expect.equal(
            childCall.request.responseFormat,
            .text,
            "String-output worker must use text response format, not JSON schema"
        )
        try Expect.equal(
            childCall.selection.preferences.preferredModelID?.rawValue,
            "fixture.application.model",
            "Actual child model call retains the inherited preferred model"
        )
        let forwardedResults = textCalls.last?.request.messages
            .flatMap(\.content.blocks)
            .compactMap { block -> ToolCall.Response? in
                if case .tool_result(let response) = block { return response }
                return nil
            } ?? []
        try Expect.equal(
            forwardedResults.first?.output,
            .string("child-text-response"),
            "Plain child text is wrapped as a JSON string tool result"
        )
        try Expect.true(
            forwardedResults.first?.isError == false,
            "Successful text delegation is not recorded as a tool error"
        )

        // Regression: an interrupted child returns through the parent's
        // suspended checkpoint using the same admitted output contract.
        let resumeState = try runtime.realizeAgent(
            identifiedBy: DelegationRootFixture.identifier
        ).makeCapabilityState()
        _ = await resumeState.reveal(.init(agents: [DelegationLeafFixture.identifier]))
        let resumeInventory = CapabilityInventory(installed: runtime.installed, state: resumeState)
        let resumeProjection = try await resumeInventory.modelProjection()
        let resumeFunction = try Expect.notNil(
            resumeProjection.name(for: .agent(DelegationLeafFixture.identifier)),
            "Resumable Agent is projected as a model-callable capability"
        )
        let resumeDelegation = try AgentDelegation(
            runtime: runtime,
            root: DelegationRootFixture.identifier,
            sessionID: "resume-parent",
            capabilityState: resumeState,
            childRunLimits: .init(iterations: 0)
        )
        let resumeRecorder = DelegatedTextRouteRecorder()
        let resumeHistory = DelegatedCheckpointStore()
        let resumeRunner = AgentRunner(
            model: .init(
                invoker: DelegatedTextRouteInvoker(
                    recorder: resumeRecorder,
                    function: resumeFunction
                ),
                selection: model.selection
            ),
            configuration: .init(historyPersistenceMode: .checkpointmutation),
            inventory: resumeInventory,
            delegation: resumeDelegation,
            recording: .init(historyStore: resumeHistory)
        )
        let firstParent = try await resumeRunner.run(
            .init(messages: [Message(role: .user, text: "Delegate and suspend")]),
            sessionID: "resume-parent"
        )
        try Expect.true(
            firstParent.suspension != nil,
            "Child run limit suspension is mirrored into the parent checkpoint"
        )
        let pendingChild = try Expect.notNil(
            await resumeDelegation.sessions().first(where: { $0.parentSessionID == "resume-parent" }),
            "Resumable child session is registered"
        )
        let interruptedChild = try await resumeDelegation.interruptWorker(
            pendingChild.id,
            mode: .urgent,
            reason: "delegation conversion regression"
        )
        try Expect.true(interruptedChild?.isInterrupted == true,
            "Suspended child becomes terminal without rerunning")
        let resumedParent = try await resumeRunner.resume(sessionID: "resume-parent")
        try Expect.true(resumedParent.isCompleted,
            "Parent resumes after stopped child using the original output contract")
        let resumeInvocations = await resumeRecorder.snapshot()
        try Expect.equal(resumeInvocations.count, 2,
            "Parent resumes once without invoking the stopped child model")
        let resumedResults = resumeInvocations.last?.request.messages
            .flatMap(\.content.blocks)
            .compactMap { block -> ToolCall.Response? in
                if case .tool_result(let response) = block { return response }
                return nil
            } ?? []
        try Expect.true(resumedResults.first?.isError == true,
            "Interrupted child remains an error-valued tool result")
        if case .object(let output)? = resumedResults.first?.output {
            try Expect.equal(output["phase"], .string("interrupted"),
                "Resumed parent receives interrupted child phase")
        } else {
            try Expect.true(false, "Interrupted child result retains its structured error envelope")
        }

        let noAuthority = CapabilityDispatcher(
            inventory: inventory,
            services: .init(model: model),
            parentSessionID: "model-parent"
        )
        var rejectedWithoutDelegation = false
        do {
            _ = try await noAuthority.invoke(
                .agent(
                    identifier: DelegationLeafFixture.identifier,
                    request: .init(messages: []),
                    sessionID: "unauthorized-child"
                ),
                origin: .model(projection: projection, function: function)
            )
        } catch CapabilityInvocationError.agentRequiresDelegation {
            rejectedWithoutDelegation = true
        }
        try Expect.true(rejectedWithoutDelegation,
            "Agent capability cannot run without an admitted delegation authority")

        let limitedState = try runtime.realizeAgent(
            identifiedBy: DelegationRootFixture.identifier
        ).makeCapabilityState()
        let limited = try AgentDelegation(
            runtime: runtime,
            root: DelegationRootFixture.identifier,
            sessionID: "limit-parent",
            capabilityState: limitedState,
            childRunLimits: .init(iterations: 0)
        )
        let checkpointStore = DelegatedCheckpointStore()
        let limitedChild = try await limited.run(
            DelegationLeafFixture.identifier,
            request: .init(messages: [Message(role: .user, text: "hold for limit")]),
            from: "limit-parent",
            sessionID: "limit-child",
            model: model,
            configuration: .init(
                runLimits: .unlimited,
                historyPersistenceMode: .checkpointmutation
            ),
            recording: .init(historyStore: checkpointStore)
        )
        try Expect.true(limitedChild.suspension != nil,
            "Child-only run limits suspend independent of parent configuration")
        let stopped = try await limited.interruptWorker(
            "limit-child", mode: .urgent, reason: "selective test"
        )
        try Expect.true(stopped?.isInterrupted == true,
            "Suspended worker can be interrupted individually")
        let snapshot = await limited.snapshots().first {
            $0.session.id == "limit-child"
        }
        try Expect.true(snapshot?.settled == true,
            "Interrupted child releases its concurrency reservation")
        let next = try await limited.begin(
            DelegationLeafFixture.identifier,
            from: "limit-parent",
            sessionID: "second-child"
        )
        try Expect.equal(next.parentSessionID, "limit-parent",
            "A second direct worker may start after interruption")
        var rejectedResume = false
        do {
            _ = try await limited.resume("limit-child")
        } catch AgentDelegation.Failure.settledSession {
            rejectedResume = true
        }
        try Expect.true(rejectedResume,
            "Interrupted workers cannot resume after terminal settlement")

        return []
    }
}
