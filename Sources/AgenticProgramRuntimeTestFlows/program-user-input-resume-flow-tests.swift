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
        summary: "Proves Program-native required and optional user input across durable Runtime suspension and deterministic replay."
    )

    func run(
        _ input: String,
        in context: AgentProgramContext
    ) async throws -> String {
        let required = try await context.ask(
            UserInputRequest(
                prompt: "Provide the required continuation value."
            )
        )

        guard let requiredAnswer = required.answer,
              case .text(let requiredValue) = requiredAnswer
        else {
            return "\(input):invalid_required"
        }

        let optional = try await context.ask(
            UserInputRequest(
                prompt: "Provide the optional continuation value.",
                requirement: .optional
            )
        )

        if optional.isSkipped {
            return "\(input):\(requiredValue):skipped"
        }

        guard let optionalAnswer = optional.answer,
              case .text(let optionalValue) = optionalAnswer
        else {
            return "\(input):\(requiredValue):invalid_optional"
        }

        return "\(input):\(requiredValue):\(optionalValue)"
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
            input: "seed",
            sessionID: "fixture-program-user-input-resume"
        )

        try Expect.equal(
            initial.record.outcome,
            .suspended,
            "first required ask suspends Program execution"
        )

        let firstCheckpoint = try Expect.notNil(
            initial.record.checkpoint,
            "required ask produces a durable checkpoint"
        )
        let firstRequest = try Expect.notNil(
            initial.interactionRequest,
            "required ask exposes an interaction request"
        )
        let requiredRequest = try Expect.notNil(
            firstRequest.requirement.pendingUserInput,
            "required interaction preserves its semantic user-input request"
        )

        try Expect.equal(
            firstRequest.kind,
            .user_input,
            "first Program suspension is user input rather than approval"
        )
        try Expect.equal(
            requiredRequest.requirement,
            .required,
            "first Program ask defaults to required"
        )
        try Expect.equal(
            firstCheckpoint.completedSteps.count,
            0,
            "no Program step precedes the first suspended ask"
        )
        try Expect.equal(
            firstCheckpoint.suspendedStep.index,
            0,
            "first required ask occupies semantic step zero"
        )
        try Expect.equal(
            firstCheckpoint.suspendedStep.kind,
            .user_input,
            "first suspended Program step is user input"
        )

        let durableFirstCheckpoint = try JSONToolBridge.decode(
            AgentProgramCheckpoint.self,
            from: try JSONToolBridge.encode(
                firstCheckpoint
            )
        )

        var requiredSkipRejected = false

        do {
            _ = try await runner.resume(
                ProgramUserInputResumeFixture(),
                from: durableFirstCheckpoint,
                interaction: AgentInteraction.Response(
                    request: firstRequest,
                    resolution: .user_input(
                        .skip
                    )
                )
            )
        } catch UserInputError.requiredInputCannotBeSkipped {
            requiredSkipRejected = true
        }

        try Expect.equal(
            requiredSkipRejected,
            true,
            "required Program input rejects explicit skip before replay resumes"
        )

        let afterRequiredAnswer = try await runner.resume(
            ProgramUserInputResumeFixture(),
            from: durableFirstCheckpoint,
            interaction: AgentInteraction.Response(
                request: firstRequest,
                resolution: .user_input(
                    .text(
                        "required-answer"
                    )
                )
            )
        )

        try Expect.equal(
            afterRequiredAnswer.record.outcome,
            .suspended,
            "required answer continues until the later optional ask suspends"
        )

        let secondCheckpoint = try Expect.notNil(
            afterRequiredAnswer.record.checkpoint,
            "second ask produces another durable checkpoint"
        )
        let secondRequest = try Expect.notNil(
            afterRequiredAnswer.interactionRequest,
            "second ask exposes its interaction request"
        )
        let optionalRequest = try Expect.notNil(
            secondRequest.requirement.pendingUserInput,
            "second interaction preserves its semantic user-input request"
        )

        try Expect.equal(
            optionalRequest.requirement,
            .optional,
            "second Program ask is explicitly optional"
        )
        try Expect.equal(
            secondCheckpoint.completedSteps.count,
            1,
            "second checkpoint contains the completed first ask"
        )
        try Expect.equal(
            secondCheckpoint.completedSteps[0].index,
            0,
            "completed required ask retains semantic step zero"
        )
        try Expect.equal(
            secondCheckpoint.completedSteps[0].kind,
            .user_input,
            "completed required ask remains a user-input step"
        )
        try Expect.equal(
            secondCheckpoint.suspendedStep.index,
            1,
            "later optional ask occupies semantic step one"
        )
        try Expect.equal(
            secondCheckpoint.suspendedStep.kind,
            .user_input,
            "second suspended Program step is user input"
        )

        let firstRecordedReply = try JSONToolBridge.decode(
            UserInputReply.self,
            from: try Expect.notNil(
                secondCheckpoint.completedSteps[0].output,
                "completed required step stores its reply"
            )
        )

        try Expect.equal(
            firstRecordedReply,
            .text(
                "required-answer"
            ),
            "required answer is durably recorded before the second suspension"
        )

        let durableSecondCheckpoint = try JSONToolBridge.decode(
            AgentProgramCheckpoint.self,
            from: try JSONToolBridge.encode(
                secondCheckpoint
            )
        )

        let optionalAnswerResult = try await runner.resume(
            ProgramUserInputResumeFixture(),
            from: durableSecondCheckpoint,
            interaction: AgentInteraction.Response(
                request: secondRequest,
                resolution: .user_input(
                    .text(
                        "optional-answer"
                    )
                )
            )
        )

        try Expect.equal(
            optionalAnswerResult.record.outcome,
            .succeeded,
            "optional answer completes the Program"
        )

        let optionalAnswerOutput = try Expect.notNil(
            optionalAnswerResult.output,
            "optional-answer branch returns Program output"
        )

        try Expect.equal(
            optionalAnswerOutput,
            "seed:required-answer:optional-answer",
            "Program continues after both answered asks"
        )
        try Expect.equal(
            optionalAnswerResult.record.steps.count,
            2,
            "optional-answer continuation contains exactly two semantic ask steps"
        )
        try Expect.equal(
            optionalAnswerResult.record.steps[0].index,
            0,
            "replayed required answer remains step zero"
        )
        try Expect.equal(
            optionalAnswerResult.record.steps[1].index,
            1,
            "resumed optional answer remains step one"
        )
        try Expect.equal(
            optionalAnswerResult.record.steps[0].kind,
            .user_input,
            "replayed first step retains user-input identity"
        )
        try Expect.equal(
            optionalAnswerResult.record.steps[1].kind,
            .user_input,
            "resumed second step retains user-input identity"
        )

        let replayedRequiredReply = try JSONToolBridge.decode(
            UserInputReply.self,
            from: try Expect.notNil(
                optionalAnswerResult.record.steps[0].output,
                "optional-answer branch retains replayed required reply"
            )
        )
        let recordedOptionalAnswer = try JSONToolBridge.decode(
            UserInputReply.self,
            from: try Expect.notNil(
                optionalAnswerResult.record.steps[1].output,
                "optional-answer branch records second reply"
            )
        )

        try Expect.equal(
            replayedRequiredReply,
            .text(
                "required-answer"
            ),
            "second resume replays the prior required answer rather than requesting it again"
        )
        try Expect.equal(
            recordedOptionalAnswer,
            .text(
                "optional-answer"
            ),
            "optional answer remains an answered reply rather than skip"
        )

        let optionalSkipResult = try await runner.resume(
            ProgramUserInputResumeFixture(),
            from: durableSecondCheckpoint,
            interaction: AgentInteraction.Response(
                request: secondRequest,
                resolution: .user_input(
                    .skip
                )
            )
        )

        try Expect.equal(
            optionalSkipResult.record.outcome,
            .succeeded,
            "explicit skip of optional Program input completes execution"
        )

        let optionalSkipOutput = try Expect.notNil(
            optionalSkipResult.output,
            "optional-skip branch returns Program output"
        )

        try Expect.equal(
            optionalSkipOutput,
            "seed:required-answer:skipped",
            "Program observes explicit optional skip distinctly from an answer"
        )
        try Expect.equal(
            optionalSkipResult.record.steps.count,
            2,
            "optional-skip continuation also contains exactly two semantic ask steps"
        )
        try Expect.equal(
            optionalSkipResult.record.steps[0].index,
            0,
            "optional-skip branch replays required step zero"
        )
        try Expect.equal(
            optionalSkipResult.record.steps[1].index,
            1,
            "optional-skip branch resolves optional step one"
        )

        let skipBranchRequiredReply = try JSONToolBridge.decode(
            UserInputReply.self,
            from: try Expect.notNil(
                optionalSkipResult.record.steps[0].output,
                "optional-skip branch retains replayed required reply"
            )
        )
        let recordedOptionalSkip = try JSONToolBridge.decode(
            UserInputReply.self,
            from: try Expect.notNil(
                optionalSkipResult.record.steps[1].output,
                "optional-skip branch records second reply"
            )
        )

        try Expect.equal(
            skipBranchRequiredReply,
            .text(
                "required-answer"
            ),
            "optional-skip branch replays the same completed required step"
        )
        try Expect.equal(
            recordedOptionalSkip,
            .skip,
            "optional skip is durably distinct from an empty or absent answer"
        )

        return [
            .field(
                "required_skip_rejected",
                String(requiredSkipRejected)
            ),
            .field(
                "second_step_index",
                String(secondCheckpoint.suspendedStep.index)
            ),
            .field(
                "optional_answer_output",
                optionalAnswerOutput
            ),
            .field(
                "optional_skip_output",
                optionalSkipOutput
            ),
            .field(
                "answer_steps",
                String(optionalAnswerResult.record.steps.count)
            ),
            .field(
                "skip_steps",
                String(optionalSkipResult.record.steps.count)
            ),
        ]
    }
}
