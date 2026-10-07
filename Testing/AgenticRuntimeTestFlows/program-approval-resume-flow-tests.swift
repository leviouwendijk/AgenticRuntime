import Agentic
import AgenticRuntime
import Foundation
import Primitives
import Schema
import Macros
import TestFlows
import Workspace

private actor ProgramReplayProbe {
    private var inferenceExecutions = 0
    private var mutationExecutions = 0
    private var tailExecutions = 0
    private var preflightRevision = "v1"

    func recordInference() {
        inferenceExecutions += 1
    }

    func recordMutation() {
        mutationExecutions += 1
    }

    func recordTail() {
        tailExecutions += 1
    }

    func setPreflightRevision(
        _ revision: String
    ) {
        preflightRevision = revision
    }

    func revision() -> String {
        preflightRevision
    }

    func counts() -> (
        inference: Int,
        mutation: Int,
        tail: Int
    ) {
        (
            inferenceExecutions,
            mutationExecutions,
            tailExecutions
        )
    }
}

@JSONSchema
private struct ProgramReplayInput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

@JSONSchema
private struct ProgramReplayInferenceOutput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

@JSONSchema
private struct ProgramReplayToolInput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

@JSONSchema
private struct ProgramReplayToolOutput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

@JSONSchema
private struct ProgramReplayOutput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private enum ProgramReplayInference:
    Inference
{
    typealias Input = ProgramReplayInput
    typealias Output = ProgramReplayInferenceOutput

    static let definition = InferenceDefinition(
        identifier: "fixture.program_replay.prepare",
        purpose: "Prepare deterministic fixture data before a governed Program effect."
    )
}

private enum ProgramReplayRealization:
    InferenceRealization
{
    typealias InferenceType = ProgramReplayInference

    static let strategy: InferenceStrategyIdentifier =
        "fixture.program_replay"
    static let instructions =
        "Produce deterministic replay fixture output."
    static let budget: InferenceBudget = .singleAttempt

    static let definition =
        InferenceRealizationDefinition<InferenceType>(
            identifier: "fixture.program_replay.realization",
            configuration: .init(
                strategy: strategy,
                instructions: instructions,
                budget: budget
            )
        )
}

private struct ProgramReplayProgram:
    Program
{
    typealias Input = ProgramReplayInput
    typealias Output = ProgramReplayOutput

    static let preparationSite = InferenceSite<
        ProgramReplayProgram,
        ProgramReplayInference
    >(
        identifier: "fixture.program_replay.preparation"
    )

    static let definition = ProgramDefinition(
        identifier: "fixture.program_replay",
        purpose: "Proves suspended native Programs resume by deterministic semantic-step replay.",
        title: "Program replay fixture"
    )

    func run(
        _ input: Input,
        in context: ProgramContext
    ) async throws -> Output {
        let prepared = try await context.infer(
            Self.preparationSite,
            input: input
        )
        let mutation = try await context.invoke(
            ToolIdentifier(
                "fixture.program_replay.mutation"
            ),
            input: ProgramReplayToolInput(
                value: prepared.value
            ),
            as: ProgramReplayToolOutput.self
        )
        let tail = try await context.invoke(
            ToolIdentifier(
                "fixture.program_replay.tail"
            ),
            input: ProgramReplayToolInput(
                value: mutation.value
            ),
            as: ProgramReplayToolOutput.self
        )

        return .init(
            value: tail.value
        )
    }
}

private struct ProgramReplayInferenceExecutor:
    InferenceExecuting
{
    let probe: ProgramReplayProbe

    func execute(
        _ invocation: InferenceInvocation
    ) async throws -> InferenceInvocationResult {
        let decoded = try JSONDecoder().decode(
            ProgramReplayInput.self,
            from: invocation.input
        )

        await probe.recordInference()

        let output = ProgramReplayInferenceOutput(
            value: "prepared:\(decoded.value)"
        )

        return .init(
            output: try JSONEncoder().encode(output),
            record: InferenceExecutionRecord(
                inference: invocation.definition.identifier,
                strategy: invocation.realization.strategy,
                budget: invocation.realization.budget,
                metadata: [
                    "fixture": "program_replay",
                ]
            )
        )
    }
}

private struct ProgramReplayMutationTool:
    Tool
{
    typealias Input = ProgramReplayToolInput
    typealias Output = ProgramReplayToolOutput

    let identifier: ToolIdentifier =
        "fixture.program_replay.mutation"
    let description =
        "Fixture mutation that may execute only after Program approval resume."
    let risk: ActionRisk = .boundedmutate

    static let definition = ToolDefinition(
        identifier: "fixture.program_replay.mutation",
        purpose: "Fixture mutation that may execute only after Program approval resume.",
        risk: .boundedmutate
    )

    let probe: ProgramReplayProbe

    func preflight(
        _ input: Input,
        in _: ToolContext
    ) async throws -> ToolPreflight {
        _ = input
        let revision = await probe.revision()

        return ToolPreflight(
            tool: identifier,
            risk: risk,
            summary: "Program replay mutation preflight \(revision)"
        )
    }

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        await probe.recordMutation()

        return .init(
            value: "mutated:\(input.value)"
        )
    }
}

private struct ProgramReplayTailTool:
    Tool
{
    typealias Input = ProgramReplayToolInput
    typealias Output = ProgramReplayToolOutput

    let identifier: ToolIdentifier =
        "fixture.program_replay.tail"
    let description =
        "Observe fixture proving Program execution continues after resume."
    let risk: ActionRisk = .observe

    static let definition = ToolDefinition(
        identifier: "fixture.program_replay.tail",
        purpose: "Observe fixture proving Program execution continues after resume.",
        risk: .observe
    )

    let probe: ProgramReplayProbe

    func preflight(
        _ input: Input,
        in _: ToolContext
    ) async throws -> ToolPreflight {
        _ = input

        return ToolPreflight(
            tool: identifier,
            risk: risk,
            summary: description
        )
    }

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        await probe.recordTail()

        return .init(
            value: "tail:\(input.value)"
        )
    }
}

private enum ProgramReplayFixtureError:
    Error
{
    case missing_checkpoint
    case missing_interaction_request
}

extension AgenticProgramRuntimeFlowTesting {
    static func runProgramApprovalResumeReplay()
        async throws
        -> [TestDiagnostic]
    {
        let realization = try programReplayRealization()
        let approvedProbe = ProgramReplayProbe()
        let approvedRunner = try programReplayRunner(
            probe: approvedProbe
        )
        let initial = try await approvedRunner.execute(
            ProgramReplayProgram(),
            input: .init(
                value: "approved"
            ),
            realization: realization,
            sessionID: "fixture-program-replay-approved"
        )

        try Expect.equal(
            initial.record.outcome,
            .suspended,
            "approval-gated Program suspends instead of failing"
        )
        try Expect.equal(
            initial.record.failure == nil,
            true,
            "Program approval suspension is not recorded as failure"
        )
        try Expect.equal(
            initial.record.steps.count,
            2,
            "initial run records completed inference plus suspended tool"
        )

        let initialCounts = await approvedProbe.counts()

        try Expect.equal(
            initialCounts.inference,
            1,
            "pre-approval inference executes once"
        )
        try Expect.equal(
            initialCounts.mutation,
            0,
            "pending mutation does not execute before approval"
        )
        try Expect.equal(
            initialCounts.tail,
            0,
            "Program does not continue beyond suspension"
        )

        guard let checkpoint = initial.record.checkpoint else {
            throw ProgramReplayFixtureError.missing_checkpoint
        }
        guard let request = initial.interactionRequest else {
            throw ProgramReplayFixtureError.missing_interaction_request
        }

        let roundTrippedCheckpoint = try JSONValue.encoding(
            checkpoint
        ).decode(
            ProgramCheckpoint.self
        )

        try Expect.equal(
            roundTrippedCheckpoint,
            checkpoint,
            "raw Program checkpoint survives persistence round-trip"
        )

        let approved = try await approvedRunner.resume(
            ProgramReplayProgram(),
            from: roundTrippedCheckpoint,
            interaction: Run.Interaction.Response(
                request: request,
                resolution: .approval(.approved)
            )
        )
        let approvedCounts = await approvedProbe.counts()

        try Expect.equal(
            approved.record.outcome,
            .succeeded,
            "approved Program resumes to completion"
        )
        try Expect.equal(
            approvedCounts.inference,
            1,
            "completed inference is replayed rather than executed twice"
        )
        try Expect.equal(
            approvedCounts.mutation,
            1,
            "approved pending mutation executes exactly once"
        )
        try Expect.equal(
            approvedCounts.tail,
            1,
            "Program continues after approved mutation"
        )
        try Expect.equal(
            approved.record.steps.count,
            3,
            "resumed record contains replayed prefix, resumed mutation, and tail"
        )
        try Expect.equal(
            approved.record.steps[0],
            checkpoint.completedSteps[0],
            "replayed inference preserves its original execution record"
        )
        try Expect.equal(
            approved.record.sessionID,
            "fixture-program-replay-approved",
            "resume preserves Program session identity"
        )

        let approvedOutput = try (
            approved.record.output ?? .null
        ).decode(
            ProgramReplayOutput.self
        )

        try Expect.equal(
            approvedOutput.value,
            "tail:mutated:prepared:approved",
            "resumed Program returns final output"
        )

        let deniedProbe = ProgramReplayProbe()
        let deniedRunner = try programReplayRunner(
            probe: deniedProbe
        )
        let deniedInitial = try await deniedRunner.execute(
            ProgramReplayProgram(),
            input: .init(value: "denied"),
            realization: realization,
            sessionID: "fixture-program-replay-denied"
        )
        guard let deniedCheckpoint = deniedInitial.record.checkpoint else {
            throw ProgramReplayFixtureError.missing_checkpoint
        }
        guard let deniedRequest = deniedInitial.interactionRequest else {
            throw ProgramReplayFixtureError.missing_interaction_request
        }
        let denied = try await deniedRunner.resume(
            ProgramReplayProgram(),
            from: deniedCheckpoint,
            interaction: .init(
                request: deniedRequest,
                resolution: .approval(.denied)
            )
        )
        let deniedCounts = await deniedProbe.counts()

        try Expect.equal(
            denied.record.outcome,
            .failed,
            "denied resume fails closed"
        )
        try Expect.equal(
            deniedCounts.inference,
            1,
            "denied resume does not repeat completed inference"
        )
        try Expect.equal(
            deniedCounts.mutation,
            0,
            "denied pending mutation never executes"
        )
        try Expect.equal(
            deniedCounts.tail,
            0,
            "denied Program does not continue"
        )

        let skippedProbe = ProgramReplayProbe()
        let skippedRunner = try programReplayRunner(
            probe: skippedProbe
        )
        let skippedInitial = try await skippedRunner.execute(
            ProgramReplayProgram(),
            input: .init(value: "skipped"),
            realization: realization,
            sessionID: "fixture-program-replay-skipped"
        )
        guard let skippedCheckpoint = skippedInitial.record.checkpoint else {
            throw ProgramReplayFixtureError.missing_checkpoint
        }
        guard let skippedRequest = skippedInitial.interactionRequest else {
            throw ProgramReplayFixtureError.missing_interaction_request
        }
        let skipped = try await skippedRunner.resume(
            ProgramReplayProgram(),
            from: skippedCheckpoint,
            interaction: .init(
                request: skippedRequest,
                resolution: .approval(.skipped)
            )
        )
        let skippedCounts = await skippedProbe.counts()

        try Expect.equal(
            skipped.record.outcome,
            .failed,
            "skipped resume fails closed"
        )
        try Expect.equal(
            skippedCounts.inference,
            1,
            "skipped resume does not repeat inference"
        )
        try Expect.equal(
            skippedCounts.mutation,
            0,
            "skipped pending mutation never executes"
        )
        try Expect.equal(
            skippedCounts.tail,
            0,
            "skipped Program does not continue"
        )

        let staleProbe = ProgramReplayProbe()
        let staleRunner = try programReplayRunner(
            probe: staleProbe
        )
        let staleInitial = try await staleRunner.execute(
            ProgramReplayProgram(),
            input: .init(value: "stale"),
            realization: realization,
            sessionID: "fixture-program-replay-stale"
        )
        guard let staleCheckpoint = staleInitial.record.checkpoint else {
            throw ProgramReplayFixtureError.missing_checkpoint
        }
        guard let staleRequest = staleInitial.interactionRequest else {
            throw ProgramReplayFixtureError.missing_interaction_request
        }

        await staleProbe.setPreflightRevision("v2")

        let stale = try await staleRunner.resume(
            ProgramReplayProgram(),
            from: staleCheckpoint,
            interaction: .init(
                request: staleRequest,
                resolution: .approval(.approved)
            )
        )
        let staleCounts = await staleProbe.counts()

        try Expect.equal(
            stale.record.outcome,
            .failed,
            "preflight drift invalidates stored approval"
        )
        try Expect.equal(
            stale.record.failure?.message.contains(
                "stale approval was not executed"
            ) == true,
            true,
            "stale approval preserves its semantic failure"
        )
        try Expect.equal(
            staleCounts.inference,
            1,
            "stale resume does not repeat completed inference"
        )
        try Expect.equal(
            staleCounts.mutation,
            0,
            "stale approval never executes mutation"
        )
        try Expect.equal(
            staleCounts.tail,
            0,
            "stale Program does not continue"
        )

        return [
            .field(
                "initial_outcome",
                initial.record.outcome.rawValue
            ),
            .field(
                "approved_inference_executions",
                String(approvedCounts.inference)
            ),
            .field(
                "approved_mutation_executions",
                String(approvedCounts.mutation)
            ),
            .field(
                "approved_tail_executions",
                String(approvedCounts.tail)
            ),
            .field(
                "denied_mutation_executions",
                String(deniedCounts.mutation)
            ),
            .field(
                "skipped_mutation_executions",
                String(skippedCounts.mutation)
            ),
            .field(
                "stale_mutation_executions",
                String(staleCounts.mutation)
            ),
        ]
    }
}

private func programReplayRealization()
    throws
    -> ProgramRealization<ProgramReplayProgram>
{
    ProgramReplayProgram.realization {
        ProgramReplayProgram.preparationSite.use(
            ProgramReplayRealization.self
        )
    }
}

private func programReplayRunner(
    probe: ProgramReplayProbe
) throws -> ProgramRunner {
    let registry = try ToolRegistry {
        ProgramReplayMutationTool(probe: probe)
        ProgramReplayTailTool(probe: probe)
    }

    return ProgramRunner(
        services: .init(
            program: .init(
                inference: ProgramReplayInferenceExecutor(
                    probe: probe
                ),
                tools: GovernedProgramToolExecutor(
                    registry: registry,
                    policy: .init(
                        autonomyMode: .auto_observe
                    )
                )
            )
        )
    )
}
