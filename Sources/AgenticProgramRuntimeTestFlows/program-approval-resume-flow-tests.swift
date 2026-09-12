import Agentic
import AgenticExecution
import AgenticInference
import AgenticPrograms
import AgenticRuntime
import Primitives
import Schema
import SchemaMacros
import TestFlows

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

private struct ProgramReplayToolOutput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct ProgramReplayOutput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private enum ProgramReplayInference:
    AgentInference
{
    typealias Input = ProgramReplayInput
    typealias Output = ProgramReplayInferenceOutput

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.program_replay.prepare",
        purpose: "Prepare deterministic fixture data before a governed Program effect."
    )
}

private struct ProgramReplayProgram:
    AgentProgram
{
    typealias Input = ProgramReplayInput
    typealias Output = ProgramReplayOutput

    static let preparationSite: AgentInferenceSiteIdentifier =
        "fixture.program_replay.preparation"

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.program_replay",
        title: "Program replay fixture",
        summary: "Proves suspended native Programs resume by deterministic semantic-step replay.",
        version: "1"
    )

    func run(
        _ input: Input,
        in context: AgentProgramContext
    ) async throws -> Output {
        let prepared = try await context.infer(
            ProgramReplayInference.self,
            at: Self.preparationSite,
            input: input
        )
        let mutation = try await context.invoke(
            AgentToolIdentifier(
                "fixture.program_replay.mutation"
            ),
            input: ProgramReplayToolInput(
                value: prepared.value
            ),
            as: ProgramReplayToolOutput.self
        )
        let tail = try await context.invoke(
            AgentToolIdentifier(
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
    AgentProgramInferenceExecuting
{
    let probe: ProgramReplayProbe

    func infer<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentProgramInferenceExecution<Inference.Output> {
        _ = inference
        _ = realization

        let inputValue = try JSONToolBridge.encode(input)
        let decoded = try JSONToolBridge.decode(
            ProgramReplayInput.self,
            from: inputValue
        )

        await probe.recordInference()

        let outputValue = try JSONToolBridge.encode(
            ProgramReplayInferenceOutput(
                value: "prepared:\(decoded.value)"
            )
        )
        let output = try JSONToolBridge.decode(
            Inference.Output.self,
            from: outputValue
        )

        return .init(
            output: output,
            metadata: [
                "fixture": "program_replay",
            ]
        )
    }
}

private struct ProgramReplayMutationTool:
    AgentTool
{
    typealias Input = ProgramReplayToolInput
    typealias Output = ProgramReplayToolOutput

    let identifier: AgentToolIdentifier =
        "fixture.program_replay.mutation"
    let description =
        "Fixture mutation that may execute only after Program approval resume."
    let risk: ActionRisk = .boundedmutate
    let probe: ProgramReplayProbe

    func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        _ = input
        let revision = await probe.revision()

        return ToolPreflight(
            toolName: identifier.rawValue,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            summary: "Program replay mutation preflight \(revision)"
        )
    }

    func call(
        _ input: Input,
        context _: AgentToolExecutionContext
    ) async throws -> Output {
        await probe.recordMutation()

        return .init(
            value: "mutated:\(input.value)"
        )
    }
}

private struct ProgramReplayTailTool:
    AgentTool
{
    typealias Input = ProgramReplayToolInput
    typealias Output = ProgramReplayToolOutput

    let identifier: AgentToolIdentifier =
        "fixture.program_replay.tail"
    let description =
        "Observe fixture proving Program execution continues after resume."
    let risk: ActionRisk = .observe
    let probe: ProgramReplayProbe

    func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        _ = input

        return ToolPreflight(
            toolName: identifier.rawValue,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            summary: description
        )
    }

    func call(
        _ input: Input,
        context _: AgentToolExecutionContext
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
        -> [TestFlowDiagnostic]
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

        let roundTrippedCheckpoint = try JSONToolBridge.decode(
            AgentProgramCheckpoint.self,
            from: try JSONToolBridge.encode(checkpoint)
        )

        try Expect.equal(
            roundTrippedCheckpoint,
            checkpoint,
            "raw Program checkpoint survives persistence round-trip"
        )

        let approved = try await approvedRunner.resume(
            ProgramReplayProgram(),
            from: roundTrippedCheckpoint,
            interaction: AgentInteraction.Response(
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

        let approvedOutput = try JSONToolBridge.decode(
            ProgramReplayOutput.self,
            from: approved.record.output ?? .null
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
    -> AgentProgramRealization<ProgramReplayProgram>
{
    AgentProgramRealization(
        id: "fixture.program_replay.realization",
        inferences: try AgentProgramInferenceBindings(
            [
                .init(
                    site: ProgramReplayProgram.preparationSite,
                    inference: ProgramReplayInference.definition.identifier,
                    realization: AgentInferenceRealization(
                        strategy: "fixture.program_replay",
                        modelSelection: .executor,
                        instructions: "Produce deterministic replay fixture output.",
                        budget: .singleAttempt
                    )
                ),
            ]
        )
    )
}

private func programReplayRunner(
    probe: ProgramReplayProbe
) throws -> AgentProgramRunner {
    let registry = try ToolRegistry {
        ProgramReplayMutationTool(probe: probe)
        ProgramReplayTailTool(probe: probe)
    }

    return AgentProgramRunner(
        services: .init(
            program: .init(
                inference: ProgramReplayInferenceExecutor(
                    probe: probe
                ),
                tools: GovernedAgentProgramToolExecutor(
                    registry: registry,
                    policy: .init(
                        autonomyMode: .auto_observe
                    )
                )
            )
        )
    )
}
