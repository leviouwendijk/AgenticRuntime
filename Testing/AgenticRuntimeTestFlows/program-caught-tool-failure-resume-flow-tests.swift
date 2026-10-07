import Agentic
import AgenticRuntime
import Primitives
import TestFlows

private actor ProgramCaughtToolFailureProbe {
    private var calls = 0

    func recordCall() {
        calls += 1
    }

    func count() -> Int {
        calls
    }
}

private struct ProgramCaughtToolFailureExecutor:
    ProgramToolExecuting
{
    let probe: ProgramCaughtToolFailureProbe

    func invoke(
        _ identifier: ToolIdentifier,
        input: JSONValue
    ) async throws -> ToolExecutionResult {
        _ = input
        await probe.recordCall()

        throw ProgramToolFailure(
            tool: identifier,
            result: ToolResult(
                call: .init(id: "fixture-caught-tool-failure", tool: identifier),
                output: .null,
                isError: true
            )
        )
    }
}

private struct ProgramCaughtToolFailureResumeFixture:
    Program
{
    typealias Input = String
    typealias Output = String

    static let toolIdentifier:
        ToolIdentifier = "fixture.caught_tool_failure"

    static let definition = ProgramDefinition(
        identifier: "fixture.program_caught_tool_failure_resume",
        purpose: "Proves a Program-authored caught tool failure replays deterministically across a later user-input suspension.",
        title: "Program Caught Tool Failure Resume"
    )

    func run(
        _ input: String,
        in context: ProgramContext
    ) async throws -> String {
        try await context.invoke(
            Self.toolIdentifier,
            input: input,
            as: String.self
        ) { failure -> String in
            guard failure.tool == Self.toolIdentifier,
                  failure.result.call.tool
                    == Self.toolIdentifier,
                  failure.result.isError
            else {
                throw failure
            }

            let response = try await context.ask(
                UserInputRequest(
                    prompt: "Continue after the caught tool failure?",
                    input: .confirmation(
                        ConfirmationUserInput(
                            defaultValue: false,
                            confirmLabel: "Continue",
                            cancelLabel: "Stop"
                        )
                    )
                )
            )

            guard case .answered(.confirmation(true)) =
                    response.outcome
            else {
                return "\(input):declined"
            }

            return "\(input):recovered"
        }
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runProgramCaughtToolFailureResume()
        async throws
        -> [TestDiagnostic]
    {
        let probe = ProgramCaughtToolFailureProbe()
        let executor = ProgramCaughtToolFailureExecutor(
            probe: probe
        )
        let runner = ProgramRunner(
            services: .init(
                program: .init(
                    tools: executor
                )
            )
        )

        let initial = try await runner.execute(
            ProgramCaughtToolFailureResumeFixture(),
            input: "seed",
            sessionID: "fixture-caught-tool-failure-resume"
        )

        try Expect.equal(
            initial.record.outcome,
            .suspended,
            "caught tool failure may continue to a later user-input suspension"
        )

        let checkpoint = try Expect.notNil(
            initial.record.checkpoint,
            "later user input checkpoints the caught failed tool step"
        )
        let request = try Expect.notNil(
            initial.interactionRequest,
            "later user input exposes its interaction request"
        )

        try Expect.equal(
            checkpoint.completedSteps.count,
            1,
            "checkpoint prefix contains the caught tool failure"
        )

        let failedStep = checkpoint.completedSteps[0]
        let failedResult = try Expect.notNil(
            failedStep.toolResult,
            "caught tool failure retains its canonical ToolResult"
        )

        try Expect.equal(
            failedStep.kind,
            .tool(
                ProgramCaughtToolFailureResumeFixture
                    .toolIdentifier
            ),
            "caught failure remains the original semantic tool step"
        )
        try Expect.equal(
            failedStep.failure?.type,
            String(reflecting: ProgramToolFailure.self),
            "caught failure remains typed as ProgramToolFailure"
        )
        try Expect.equal(
            failedResult.call.tool,
            ProgramCaughtToolFailureResumeFixture
                .toolIdentifier,
            "durable failed result retains exact tool identity"
        )
        try Expect.equal(
            failedResult.isError,
            true,
            "durable failed result remains an error result"
        )
        try Expect.equal(
            checkpoint.suspendedStep.index,
            1,
            "later user input follows the caught failure in semantic order"
        )
        try Expect.equal(
            checkpoint.suspendedStep.kind,
            .user_input,
            "second semantic step is the user-input boundary"
        )
        try Expect.equal(
            await probe.count(),
            1,
            "initial execution invokes the failed tool exactly once"
        )

        let durableCheckpoint = try JSONValue.encoding(
            checkpoint
        ).decode(
            ProgramCheckpoint.self
        )

        let resumed = try await runner.resume(
            ProgramCaughtToolFailureResumeFixture(),
            from: durableCheckpoint,
            interaction: Run.Interaction.Response(
                request: request,
                resolution: .user_input(
                    .confirmation(true)
                )
            )
        )

        try Expect.equal(
            resumed.record.outcome,
            .succeeded,
            "replaying the caught failure re-enters authored recovery and completes"
        )
        let resumedOutput = try Expect.notNil(
            resumed.output,
            "successful replay returns the authored recovery output"
        )

        try Expect.equal(
            resumedOutput,
            "seed:recovered",
            "authored recovery receives the reconstructed tool failure"
        )
        try Expect.equal(
            await probe.count(),
            1,
            "resume replays failure evidence without re-executing the tool"
        )
        try Expect.equal(
            resumed.record.steps.count,
            2,
            "resumed trace preserves the failed tool and resolved user-input steps"
        )
        try Expect.equal(
            resumed.record.steps[0].toolResult,
            failedResult,
            "replayed failed step preserves the exact canonical tool result"
        )

        return [
            .field(
                "tool_calls",
                String(
                    await probe.count()
                )
            ),
            .field(
                "steps",
                String(
                    resumed.record.steps.count
                )
            ),
            .field(
                "output",
                resumedOutput
            ),
        ]
    }
}
