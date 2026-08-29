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
}

private extension AgenticRuntimeToolPlanFlowTesting {
    struct Fixture {
        let coordinator: AgentToolPlanRunCoordinator
        let parentPlan: AgentToolPlan
        let recoveryPlan: AgentToolPlan
        let probe: RuntimeToolPlanProbe
    }

    static func makeFixture() throws -> Fixture {
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
            )
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
    private var repairFailed = false

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

        if input.marker == "repair",
           !repairFailed
        {
            repairFailed = true
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
}
