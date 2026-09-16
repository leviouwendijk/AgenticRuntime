import Agentic
import AgenticPrograms
import AgenticRuntime
import TestFlows

private struct ProgramUserInputResumeFixture: AgentProgram {
    typealias Input = String
    typealias Output = String

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.program_user_input_resume",
        title: "Program User Input Resume",
        summary: "Proves native Program user input suspends and resumes through Runtime replay."
    )

    func run(
        _ input: String,
        in context: AgentProgramContext
    ) async throws -> String {
        let response = try await context.ask(
            UserInputRequest(
                prompt: "Provide the continuation value."
            )
        )

        guard let answer = response.answer,
              case .text(let value) = answer
        else {
            return "\(input):skipped"
        }

        return "\(input):\(value)"
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runProgramUserInputResume()
        async throws
        -> [TestFlowDiagnostic]
    {
        let runner = AgentProgramRunner()
        let initial = try await runner.execute(
            ProgramUserInputResumeFixture(),
            input: "before",
            sessionID: "fixture-program-user-input-resume"
        )

        try Expect.equal(
            initial.record.outcome,
            .suspended,
            "Program-native ask suspends execution"
        )

        let checkpoint = try Expect.notNil(
            initial.record.checkpoint,
            "Program-native ask produces a durable checkpoint"
        )
        let request = try Expect.notNil(
            initial.interactionRequest,
            "Program-native ask exposes an interaction request"
        )
        let pending = try Expect.notNil(
            request.requirement.pendingUserInput,
            "Program-native ask exposes the exact semantic user-input request"
        )

        try Expect.equal(
            request.kind,
            .user_input,
            "Program-native ask is a user-input interaction rather than an approval"
        )
        try Expect.equal(
            pending.prompt,
            "Provide the continuation value.",
            "Program-native ask preserves the authored prompt"
        )
        try Expect.equal(
            checkpoint.suspendedStep.kind,
            .user_input,
            "Program checkpoint records user input as its own semantic step kind"
        )

        let roundTrippedCheckpoint = try JSONToolBridge.decode(
            AgentProgramCheckpoint.self,
            from: try JSONToolBridge.encode(
                checkpoint
            )
        )

        let resumed = try await runner.resume(
            ProgramUserInputResumeFixture(),
            from: roundTrippedCheckpoint,
            interaction: AgentInteraction.Response(
                request: request,
                resolution: .user_input(
                    .text(
                        "continue"
                    )
                )
            )
        )

        try Expect.equal(
            resumed.record.outcome,
            .succeeded,
            "Program-native user input resumes the suspended Program"
        )
        let resumedOutput = try Expect.notNil(
            resumed.output,
            "resumed Program returns typed output"
        )

        try Expect.equal(
            resumedOutput,
            "before:continue",
            "Program continues with the refined user-input response"
        )
        try Expect.equal(
            resumed.record.steps.count,
            1,
            "resumed Program replaces the suspended user-input step with one completed step"
        )
        try Expect.equal(
            resumed.record.steps[0].kind,
            .user_input,
            "completed Program trace preserves user-input step identity"
        )

        let recordedReply = try JSONToolBridge.decode(
            UserInputReply.self,
            from: try Expect.notNil(
                resumed.record.steps[0].output,
                "completed user-input step stores its durable reply"
            )
        )

        try Expect.equal(
            recordedReply,
            .text(
                "continue"
            ),
            "completed user-input step stores the exact loose reply used for refinement"
        )

        return [
            .field(
                "initial_outcome",
                initial.record.outcome.rawValue
            ),
            .field(
                "interaction_kind",
                request.kind.rawValue
            ),
            .field(
                "resumed_outcome",
                resumed.record.outcome.rawValue
            ),
            .field(
                "output",
                resumedOutput
            ),
        ]
    }
}
