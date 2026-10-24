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

extension AgenticProgramRuntimeFlowTesting {
    static func runAgentDelegationExecution() async throws -> [TestDiagnostic] {
        let application = Agentic.application("fixture.delegation.execution") {
            install(DelegationRootFixture.self)
            install(DelegationIntermediateFixture.self)
            install(DelegationLeafFixture.self)
            install(DelegationExcludedFixture.self)
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
        let model = RuntimeServices.Model(invoker: DelegatedExecutionModel(recorder: recorder))
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
            calls.first?.request.tools.count,
            0,
            "Child model projection respects its own authored visibility"
        )
        let lineage = await admission.session("real-child")
        try Expect.equal(lineage?.parentSessionID, "real-parent", "Executed child keeps parent lineage")

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

        return []
    }
}
