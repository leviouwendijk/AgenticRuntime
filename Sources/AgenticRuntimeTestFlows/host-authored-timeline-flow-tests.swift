import Agentic
import AgenticExecution
import AgenticInterfaces
import AgenticRuntime
import AgenticRuntimeCommands
import TestFlows

enum AgenticRuntimeHostAuthoredTimelineFlowTesting {
    enum Failure:
        Error
    {
        case missingRun
    }

    static func runPausedFutureStepProjection()
        throws -> [TestFlowDiagnostic]
    {
        let first = AgentToolCall(
            id: "host-authored-first",
            name: "host_authored_first",
            input: try JSONToolBridge.encode(
                FixtureInput(
                    marker: "first"
                )
            )
        )
        let second = AgentToolCall(
            id: "host-authored-second",
            name: "host_authored_second",
            input: try JSONToolBridge.encode(
                FixtureInput(
                    marker: "second"
                )
            )
        )
        let plan = AgentToolPlan(
            id: "host-authored-timeline-plan",
            root: .sequence(
                [
                    .call(
                        first
                    ),
                    .batch(
                        [
                            .call(
                                second
                            ),
                        ]
                    ),
                ]
            )
        )
        let run = AgentToolPlanRun(
            id: "host-authored-timeline-run",
            plan: plan,
            relationship: .root,
            attempts: [
                AgentToolPlanAttempt(
                    number: 1,
                    scope: .plan,
                    result: AgentToolPlanResult(
                        planID: plan.id,
                        outcome: .succeeded,
                        records: [
                            AgentToolPlanRecord(
                                path: "root.sequence[0]",
                                call: first,
                                outcome: .succeeded
                            ),
                        ]
                    )
                ),
            ],
            revision: 2,
            state: .paused(
                AgentToolPlanPause(
                    afterPath: "root.sequence[0]",
                    afterCallID: first.id,
                    attemptNumber: 1,
                    reason: .single_step
                )
            )
        )
        let snapshot = HostProjection.snapshot(
            runs: [
                run,
            ],
            context: "authored timeline projection"
        )

        guard let presentation = snapshot.runs.first else {
            throw Failure.missingRun
        }

        try Expect.equal(
            presentation.steps.count,
            2,
            "paused run preserves all authored call rows"
        )
        try Expect.equal(
            presentation.steps[0].id,
            first.id,
            "first authored call remains first"
        )
        try Expect.equal(
            presentation.steps[0].state,
            .completed,
            "attempted first call overlays completed state"
        )
        try Expect.equal(
            presentation.steps[1].id,
            second.id,
            "future authored batch call remains visible"
        )
        try Expect.equal(
            presentation.steps[1].state,
            .pending,
            "future authored call remains pending after single-step pause"
        )

        return [
            .field(
                "steps",
                "\(presentation.steps.count)"
            ),
            .field(
                "first",
                presentation.steps[0].state.rawValue
            ),
            .field(
                "future",
                presentation.steps[1].state.rawValue
            ),
        ]
    }
}

private extension AgenticRuntimeHostAuthoredTimelineFlowTesting {
    struct FixtureInput:
        Sendable,
        Codable,
        Hashable
    {
        let marker: String
    }
}
