import Agentic
import AgenticInference
import AgenticPrograms
import AgenticRecovery
import AgenticRuntime
import Foundation
import Primitives
import TestFlows

private enum RuntimeInferenceFailureMode:
    String,
    Sendable,
    Codable,
    Hashable
{
    case classified
    case unclassified
}

private struct RuntimeInferenceFailureInput:
    Sendable,
    Codable,
    Hashable
{
    let mode: RuntimeInferenceFailureMode
}

private enum RuntimeInferenceFailureFixtureInference:
    AgentInference
{
    typealias Input = RuntimeInferenceFailureInput
    typealias Output = String

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.runtime_inference_failure",
        purpose: "Fail deterministically to prove Runtime Program inference failure evidence."
    )
}

private enum RuntimeInferenceFailureFixtureError:
    Error,
    Sendable,
    LocalizedError
{
    case unclassified

    var errorDescription: String? {
        "fixture unclassified inference failure"
    }
}

private actor RuntimeInferenceFailureProbe {
    private var executions = 0

    func record() {
        executions += 1
    }

    func count() -> Int {
        executions
    }
}

private struct RuntimeInferenceFailureExecutor:
    AgentInferenceExecuting
{
    let probe: RuntimeInferenceFailureProbe

    func execute<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws
        -> AgentInferenceExecutionResult<Inference.Output>
    {
        _ = inference
        _ = realization

        let encoded = try JSONToolBridge.encode(
            input
        )
        let fixture = try JSONToolBridge.decode(
            RuntimeInferenceFailureInput.self,
            from: encoded
        )

        await probe.record()

        switch fixture.mode {
        case .classified:
            let message =
                "fixture classified inference failure"
            let recovery = Recovery.Record(
                incident: Recovery.Incident(
                    kind: .transport_transient,
                    stage: .execution,
                    effectState: Recovery.EffectState.none,
                    retrySafety: .safe,
                    scope: .init(
                        kind: .inference,
                        identifier:
                            RuntimeInferenceFailureFixtureInference
                                .definition
                                .identifier
                                .rawValue
                    ),
                    message: message
                ),
                plan: nil,
                attempts: [],
                outcome: .propagated
            )
            let recoveryError = AgentInferenceRecoveryError(
                record: recovery,
                message: message
            )
            let attempt = AgentInferenceAttemptFailure(
                index: 0,
                adapter: AgentInferenceAdapterIdentifier(
                    rawValue: "fixture.runtime_inference_failure.adapter"
                ),
                selection: realization.modelSelection,
                failure: AgentInferenceFailureRecord(
                    capturing: recoveryError,
                    recovery: recovery
                ),
                recoveries: [
                    recovery,
                ],
                metadata: [
                    "fixture": "runtime_program_inference_failure",
                ]
            )

            throw AgentInferenceExecutionFailure(
                attempt: attempt,
                inference: Inference.definition.identifier,
                strategy: realization.strategy,
                budget: realization.budget,
                metadata: [
                    "fixture": "runtime_program_inference_failure",
                ]
            )

        case .unclassified:
            throw RuntimeInferenceFailureFixtureError
                .unclassified
        }
    }
}

private struct RuntimeInferenceFailureProgram:
    AgentProgram
{
    typealias Input = RuntimeInferenceFailureInput
    typealias Output = String

    static let site: AgentInferenceSiteIdentifier =
        "fixture.runtime_inference_failure.site"

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.runtime_inference_failure_program",
        title: "Runtime Program inference failure",
        summary: "Proves Runtime threads typed Program inference failure evidence."
    )

    func run(
        _ input: Input,
        in context: AgentProgramContext
    ) async throws -> String {
        switch input.mode {
        case .classified:
            return try await context.infer(
                RuntimeInferenceFailureFixtureInference.self,
                at: Self.site,
                input: input
            ) { failure -> String in
                guard
                    failure.site == Self.site,
                    failure.inference ==
                        RuntimeInferenceFailureFixtureInference
                            .definition
                            .identifier,
                    failure.recovery?.incident.kind ==
                        .transport_transient,
                    failure.effect == Recovery.EffectState.none,
                    failure.retry == .safe,
                    failure.outcome == .propagated
                else {
                    throw failure
                }

                return "semantic_fallback"
            }

        case .unclassified:
            return try await context.infer(
                RuntimeInferenceFailureFixtureInference.self,
                at: Self.site,
                input: input
            ) { _ -> AgentProgramInferenceFailure.Handling<String> in
                .propagate
            }
        }
    }
}

private func runtimeInferenceFailureRealization()
    throws
    -> AgentProgramRealization<RuntimeInferenceFailureProgram>
{
    AgentProgramRealization(
        id: "fixture.runtime_inference_failure.realization",
        inferences: try AgentProgramInferenceBindings(
            [
                .init(
                    site: RuntimeInferenceFailureProgram.site,
                    inference:
                        RuntimeInferenceFailureFixtureInference
                            .definition
                            .identifier,
                    realization: AgentInferenceRealization(
                        strategy: .direct,
                        modelSelection: .executor,
                        instructions: "Fail deterministically.",
                        budget: .singleAttempt
                    )
                ),
            ]
        )
    )
}

private func runtimeInferenceFailureRunner(
    probe: RuntimeInferenceFailureProbe
) -> AgentProgramRunner {
    AgentProgramRunner(
        services: .init(
            program: .init(
                inference: RuntimeInferenceFailureExecutor(
                    probe: probe
                )
            )
        )
    )
}

private func failedInferenceStep(
    in record: AgentProgramExecutionRecord
) -> AgentProgramStepRecord? {
    record.steps.first { step in
        guard
            case .inference(
                let site,
                let inference
            ) = step.kind
        else {
            return false
        }

        return
            site == RuntimeInferenceFailureProgram.site &&
            inference ==
                RuntimeInferenceFailureFixtureInference
                    .definition
                    .identifier &&
            step.failure != nil
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runProgramInferenceFailureRecoveryEvidence()
        async throws
        -> [TestFlowDiagnostic]
    {
        let realization = try runtimeInferenceFailureRealization()

        let classifiedProbe = RuntimeInferenceFailureProbe()
        let classified = try await runtimeInferenceFailureRunner(
            probe: classifiedProbe
        ).execute(
            RuntimeInferenceFailureProgram(),
            input: .init(
                mode: .classified
            ),
            realization: realization
        )

        let classifiedOutput = try Expect.notNil(
            classified.output,
            "authored handler recovers classified Runtime inference failure"
        )
        let classifiedStep = try Expect.notNil(
            failedInferenceStep(
                in: classified.record
            ),
            "semantically recovered Program retains failed inference step"
        )
        let classifiedFailure = try Expect.notNil(
            classifiedStep.failure,
            "failed inference step records typed Program failure"
        )
        let classifiedRecovery = try Expect.notNil(
            classifiedStep.recovery,
            "failed inference step preserves classified recovery evidence"
        )
        let classifiedExecution = try Expect.notNil(
            classifiedStep.inference.execution,
            "failed inference step preserves canonical inference execution evidence"
        )
        let classifiedExecutionFailure = try Expect.notNil(
            classifiedExecution.failure,
            "failed inference execution preserves its durable failure evidence"
        )
        let classifiedExecutionRecovery = try Expect.notNil(
            classifiedExecutionFailure.recovery,
            "failed inference execution preserves its lower-level recovery evidence"
        )

        try Expect.equal(
            classified.record.outcome,
            .succeeded,
            "authored semantic fallback allows Program to succeed"
        )
        try Expect.equal(
            classifiedOutput,
            "semantic_fallback",
            "authored handler supplies semantic fallback output"
        )
        try Expect.equal(
            await classifiedProbe.count(),
            1,
            "Runtime does not invent another inference attempt during semantic fallback"
        )
        try Expect.equal(
            classifiedFailure.type,
            String(
                reflecting: AgentProgramInferenceFailure.self
            ),
            "Runtime step records canonical typed Program inference failure"
        )
        try Expect.equal(
            classifiedRecovery.incident.kind,
            .transport_transient,
            "Runtime trace preserves classified inference incident"
        )
        try Expect.equal(
            classifiedRecovery.state.effect,
            Recovery.EffectState.none,
            "Runtime trace preserves authoritative inference effect state"
        )
        try Expect.equal(
            classifiedRecovery.state.retry,
            .safe,
            "Runtime trace preserves inference retry safety"
        )
        try Expect.equal(
            classifiedRecovery.outcome,
            .propagated,
            "Runtime trace preserves propagated mechanical recovery outcome"
        )
        try Expect.equal(
            classifiedExecution.inference,
            RuntimeInferenceFailureFixtureInference
                .definition
                .identifier,
            "Runtime trace preserves the canonical failed inference identity"
        )
        try Expect.equal(
            classifiedExecution.attempts.count,
            1,
            "Runtime trace preserves the canonical failed semantic attempt"
        )
        try Expect.equal(
            classifiedExecution.metadata["fixture"],
            "runtime_program_inference_failure",
            "Runtime trace preserves lower-level failed execution metadata"
        )
        try Expect.equal(
            classifiedExecutionRecovery,
            classifiedRecovery,
            "Program step execution and recovery projections preserve the same lower-level recovery record"
        )

        let unclassifiedProbe = RuntimeInferenceFailureProbe()
        let unclassified = try await runtimeInferenceFailureRunner(
            probe: unclassifiedProbe
        ).execute(
            RuntimeInferenceFailureProgram(),
            input: .init(
                mode: .unclassified
            ),
            realization: realization
        )

        let unclassifiedStep = try Expect.notNil(
            failedInferenceStep(
                in: unclassified.record
            ),
            "propagated unclassified failure retains failed inference step"
        )
        let unclassifiedFailure = try Expect.notNil(
            unclassifiedStep.failure,
            "unclassified executor failure is wrapped as typed Program inference failure"
        )
        let rootFailure = try Expect.notNil(
            unclassified.record.failure,
            "propagated typed inference failure reaches Program execution record"
        )

        try Expect.equal(
            unclassified.output == nil,
            true,
            "propagated inference failure produces no Program output"
        )
        try Expect.equal(
            unclassified.record.outcome,
            .failed,
            "authored propagate keeps Program failure structured"
        )
        try Expect.equal(
            await unclassifiedProbe.count(),
            1,
            "unclassified failure is not retried mechanically"
        )
        try Expect.equal(
            unclassifiedFailure.type,
            String(
                reflecting: AgentProgramInferenceFailure.self
            ),
            "unclassified executor error is wrapped in canonical Program failure"
        )
        try Expect.equal(
            rootFailure.type,
            String(
                reflecting: AgentProgramInferenceFailure.self
            ),
            "root Program failure remains the canonical typed inference failure"
        )
        try Expect.equal(
            unclassifiedStep.recovery == nil,
            true,
            "Runtime does not invent recovery evidence for unclassified inference failure"
        )
        try Expect.equal(
            unclassifiedStep.inference.execution == nil,
            true,
            "fallback Program inference failure does not invent canonical execution evidence"
        )

        return [
            .field(
                "classified_outcome",
                classified.record.outcome.rawValue
            ),
            .field(
                "classified_recovery",
                classifiedRecovery.outcome.rawValue
            ),
            .field(
                "classified_calls",
                String(
                    await classifiedProbe.count()
                )
            ),
            .field(
                "classified_execution",
                String(classifiedStep.inference.execution != nil)
            ),
            .field(
                "classified_attempts",
                String(classifiedExecution.attempts.count)
            ),
            .field(
                "unclassified_outcome",
                unclassified.record.outcome.rawValue
            ),
            .field(
                "unclassified_calls",
                String(
                    await unclassifiedProbe.count()
                )
            ),
        ]
    }
}
