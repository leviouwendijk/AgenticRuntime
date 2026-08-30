import Agentic
import AgenticExecution
import AgenticRuntime
import Primitives
import TestFlows

enum AgenticRuntimeToolPlanFlowTesting {
    static func runRecoveryThenRetry() async throws -> [TestFlowDiagnostic] {
        let fixture = try makeFixture()
        let parent = try await fixture.coordinator.start(
            fixture.parentPlan,
            runID: "parent-retry"
        )

        try requireFailureSuspension(
            parent
        )

        try Expect.equal(
            await fixture.probe.invocationLog(),
            "prefix,repair",
            "parent suspends before suffix"
        )

        let recovery = try await fixture.coordinator.recover(
            parentRunID: parent.id,
            expectedParentRevision: parent.revision,
            plan: fixture.recoveryPlan,
            runID: "recovery-retry"
        )

        guard case .recovery(
            parentRunID: let recoveryParentID
        ) = recovery.relationship else {
            throw RuntimeToolPlanFlowError.unexpectedRelationship
        }

        try Expect.equal(
            recoveryParentID,
            parent.id,
            "recovery child links to suspended parent"
        )

        guard case .completed = recovery.state else {
            throw RuntimeToolPlanFlowError.unexpectedRunState
        }

        let unchangedParent = try await fixture.coordinator.run(
            id: parent.id
        )

        try requireFailureSuspension(
            unchangedParent
        )

        try Expect.equal(
            unchangedParent.revision,
            parent.revision,
            "successful recovery does not mutate parent"
        )

        try Expect.equal(
            await fixture.probe.invocationLog(),
            "prefix,repair,fix",
            "recovery executes independently from parent"
        )

        let recoveries = await fixture.coordinator.recoveries(
            of: parent.id
        )

        try Expect.equal(
            recoveries.count,
            1,
            "runtime retains recovery relationship in memory"
        )

        let retried = try await fixture.coordinator.retry(
            runID: parent.id,
            expectedRevision: unchangedParent.revision
        )

        try requireContinuationRequired(
            retried
        )

        try Expect.equal(
            await fixture.probe.invocationLog(),
            "prefix,repair,fix,repair",
            "post-fix retry executes only failed node"
        )

        let resumed = try await fixture.coordinator.resume(
            runID: parent.id,
            expectedRevision: retried.revision
        )

        guard case .completed = resumed.state else {
            throw RuntimeToolPlanFlowError.unexpectedRunState
        }

        try Expect.equal(
            await fixture.probe.invocationLog(),
            "prefix,repair,fix,repair,suffix",
            "explicit resume executes untouched suffix only"
        )

        return [
            .field(
                "parent",
                resumed.id
            ),
            .field(
                "recovery",
                recovery.id
            ),
            .field(
                "revision",
                "\(resumed.revision)"
            ),
        ]
    }

    static func runRecoveryThenSkip() async throws -> [TestFlowDiagnostic] {
        let fixture = try makeFixture()
        let parent = try await fixture.coordinator.start(
            fixture.parentPlan,
            runID: "parent-skip"
        )

        try requireFailureSuspension(
            parent
        )

        let recovery = try await fixture.coordinator.recover(
            parentRunID: parent.id,
            expectedParentRevision: parent.revision,
            plan: fixture.recoveryPlan,
            runID: "recovery-skip"
        )

        guard case .completed = recovery.state else {
            throw RuntimeToolPlanFlowError.unexpectedRunState
        }

        let unchangedParent = try await fixture.coordinator.run(
            id: parent.id
        )

        try requireFailureSuspension(
            unchangedParent
        )

        let skipped = try await fixture.coordinator.skip(
            runID: parent.id,
            expectedRevision: unchangedParent.revision
        )

        try requireContinuationRequired(
            skipped
        )

        try Expect.equal(
            await fixture.probe.invocationLog(),
            "prefix,repair,fix",
            "skip does not replay externally repaired node"
        )

        do {
            _ = try await fixture.coordinator.skip(
                runID: parent.id,
                expectedRevision: unchangedParent.revision
            )

            throw RuntimeToolPlanFlowError.expectedStaleRevision
        } catch let error as AgentToolPlanRunCoordinatorError {
            guard case .staleRevision(
                runID: let runID,
                expected: let expected,
                actual: let actual
            ) = error else {
                throw error
            }

            try Expect.equal(
                runID,
                parent.id,
                "stale control identifies parent run"
            )
            try Expect.equal(
                expected,
                unchangedParent.revision,
                "stale control retains supplied revision"
            )
            try Expect.equal(
                actual,
                skipped.revision,
                "stale control reports live revision"
            )
        }

        let resumed = try await fixture.coordinator.resume(
            runID: parent.id,
            expectedRevision: skipped.revision
        )

        guard case .completed = resumed.state else {
            throw RuntimeToolPlanFlowError.unexpectedRunState
        }

        try Expect.equal(
            await fixture.probe.invocationLog(),
            "prefix,repair,fix,suffix",
            "skip plus explicit resume executes suffix only"
        )

        return [
            .field(
                "parent",
                resumed.id
            ),
            .field(
                "resolution",
                "skipped"
            ),
            .field(
                "revision",
                "\(resumed.revision)"
            ),
        ]
    }

    static func runRecoveryHierarchyAndGating() async throws -> [TestFlowDiagnostic] {
        let fixture = try makeFixture()
        let parent = try await fixture.coordinator.start(
            fixture.parentPlan,
            runID: "hierarchy-parent"
        )
        try requireFailureSuspension(parent)

        let child = try await fixture.coordinator.recover(
            parentRunID: parent.id,
            expectedParentRevision: parent.revision,
            plan: try plan(id: "child-plan", marker: "child"),
            runID: "hierarchy-child"
        )
        try requireFailureSuspension(child)
        try Expect.equal(
            try await fixture.coordinator.recoveryDepth(of: child.id),
            1,
            "first recovery has depth one"
        )
        try Expect.equal(
            try await fixture.coordinator.activeRecovery(of: parent.id)?.id,
            child.id,
            "suspended child gates its exact parent suspension"
        )
        try await requireActiveRecoveryGate(
            parent: parent,
            child: child,
            coordinator: fixture.coordinator
        )

        do {
            _ = try await fixture.coordinator.recover(
                parentRunID: parent.id,
                expectedParentRevision: parent.revision,
                plan: fixture.recoveryPlan,
                runID: "second-child"
            )
            throw RuntimeToolPlanFlowError.expectedActiveRecoveryGate
        } catch let error as AgentToolPlanRunCoordinatorError {
            guard case .activeRecoveryChild = error else {
                throw error
            }
        }

        let grandchild = try await fixture.coordinator.recover(
            parentRunID: child.id,
            expectedParentRevision: child.revision,
            plan: fixture.recoveryPlan,
            runID: "hierarchy-grandchild"
        )
        guard case .completed = grandchild.state else {
            throw RuntimeToolPlanFlowError.unexpectedRunState
        }
        try Expect.equal(
            try await fixture.coordinator.recoveryDepth(of: grandchild.id),
            2,
            "nested recovery is allowed below the default depth cap"
        )

        let limited = try makeFixture(maximumRecoveryDepth: 1)
        let limitedParent = try await limited.coordinator.start(
            limited.parentPlan,
            runID: "depth-parent"
        )
        let limitedChild = try await limited.coordinator.recover(
            parentRunID: limitedParent.id,
            expectedParentRevision: limitedParent.revision,
            plan: try plan(id: "depth-child-plan", marker: "child"),
            runID: "depth-child"
        )
        try requireFailureSuspension(limitedChild)

        do {
            _ = try await limited.coordinator.recover(
                parentRunID: limitedChild.id,
                expectedParentRevision: limitedChild.revision,
                plan: limited.recoveryPlan,
                runID: "depth-grandchild"
            )
            throw RuntimeToolPlanFlowError.expectedRecoveryDepthLimit
        } catch let error as AgentToolPlanRunCoordinatorError {
            guard case .maximumRecoveryDepthExceeded(
                parentRunID: let parentRunID,
                maximumDepth: let maximumDepth
            ) = error,
            parentRunID == limitedChild.id,
            maximumDepth == 1 else {
                throw error
            }
        }

        return [
            .field("nested-depth", "2"),
            .field("maximum-depth", "1"),
        ]
    }
}

private extension AgenticRuntimeToolPlanFlowTesting {
    struct Fixture {
        let coordinator: AgentToolPlanRunCoordinator
        let parentPlan: AgentToolPlan
        let recoveryPlan: AgentToolPlan
        let probe: RuntimeToolPlanProbe
    }

    static func makeFixture(maximumRecoveryDepth: Int = 4) throws -> Fixture {
        let probe = RuntimeToolPlanProbe()
        let tool = ClosureAgentTool(
            identifier: "runtime_tool_plan_probe",
            description: "Records plan-run execution order and fails the first repair call."
        ) { value, _ in
            try await probe.invoke(
                value
            )
        }
        let invoker = ToolInvoker(
            registry: ToolRegistry(
                tools: [
                    tool,
                ]
            ),
            policy: ToolExecutionPolicy(
                autonomyMode: .auto_observe
            )
        )
        let coordinator = AgentToolPlanRunCoordinator(
            invoker: invoker,
            context: AgentToolExecutionContext(
                sessionID: "runtime-tool-plan-session"
            ),
            maximumRecoveryDepth: maximumRecoveryDepth
        )
        let parentPlan = AgentToolPlan(
            id: "runtime-parent-plan",
            root: .sequence(
                [
                    .call(
                        try call(
                            id: "prefix",
                            marker: "prefix"
                        )
                    ),
                    .call(
                        try call(
                            id: "repair",
                            marker: "repair"
                        )
                    ),
                    .call(
                        try call(
                            id: "suffix",
                            marker: "suffix"
                        )
                    ),
                ]
            )
        )
        let recoveryPlan = AgentToolPlan(
            id: "runtime-recovery-plan",
            root: .call(
                try call(
                    id: "fix",
                    marker: "fix"
                )
            )
        )

        return Fixture(
            coordinator: coordinator,
            parentPlan: parentPlan,
            recoveryPlan: recoveryPlan,
            probe: probe
        )
    }

    static func plan(id: String, marker: String) throws -> AgentToolPlan {
        AgentToolPlan(
            id: id,
            root: .call(try call(id: "call-\(marker)", marker: marker))
        )
    }

    static func requireActiveRecoveryGate(
        parent: AgentToolPlanRun,
        child: AgentToolPlanRun,
        coordinator: AgentToolPlanRunCoordinator
    ) async throws {
        do {
            _ = try await coordinator.retry(
                runID: parent.id,
                expectedRevision: parent.revision
            )
            throw RuntimeToolPlanFlowError.expectedActiveRecoveryGate
        } catch let error as AgentToolPlanRunCoordinatorError {
            guard case .activeRecoveryChild(
                parentRunID: let parentRunID,
                childRunID: let childRunID
            ) = error,
            parentRunID == parent.id,
            childRunID == child.id else {
                throw error
            }
        }

        do {
            _ = try await coordinator.skip(
                runID: parent.id,
                expectedRevision: parent.revision
            )
            throw RuntimeToolPlanFlowError.expectedActiveRecoveryGate
        } catch let error as AgentToolPlanRunCoordinatorError {
            guard case .activeRecoveryChild = error else { throw error }
        }
    }

    static func call(
        id: String,
        marker: String
    ) throws -> AgentToolCall {
        AgentToolCall(
            id: id,
            name: "runtime_tool_plan_probe",
            input: try JSONToolBridge.encode(
                RuntimeToolPlanProbeInput(
                    marker: marker
                )
            )
        )
    }

    static func requireFailureSuspension(
        _ run: AgentToolPlanRun
    ) throws {
        guard case .suspended(let suspension) = run.state,
              case .failure = suspension.reason
        else {
            throw RuntimeToolPlanFlowError.unexpectedRunState
        }
    }

    static func requireContinuationRequired(
        _ run: AgentToolPlanRun
    ) throws {
        guard case .suspended(let suspension) = run.state,
              case .continuation_required = suspension.reason
        else {
            throw RuntimeToolPlanFlowError.unexpectedRunState
        }
    }
}

private actor RuntimeToolPlanProbe {
    private var invocations: [String] = []
    private var failedMarkers: Set<String> = []

    func invoke(
        _ value: JSONValue
    ) throws -> JSONValue {
        let input = try JSONToolBridge.decode(
            RuntimeToolPlanProbeInput.self,
            from: value
        )

        invocations.append(
            input.marker
        )

        if ["repair", "child"].contains(input.marker),
           failedMarkers.insert(input.marker).inserted {
            throw RuntimeToolPlanProbeError.firstRepairAttempt
        }

        return value
    }

    func invocationLog() -> String {
        invocations.joined(
            separator: ","
        )
    }
}

private struct RuntimeToolPlanProbeInput:
    Sendable,
    Codable,
    Hashable
{
    let marker: String
}

private enum RuntimeToolPlanProbeError: Error {
    case firstRepairAttempt
}

private enum RuntimeToolPlanFlowError: Error {
    case unexpectedRelationship
    case unexpectedRunState
    case expectedStaleRevision
    case expectedActiveRecoveryGate
    case expectedRecoveryDepthLimit
}
