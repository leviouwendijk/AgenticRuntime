import Foundation
import Agentic
import AgenticExecution
import AgenticRecovery
import AgenticRuntime
import AgenticPrograms
import Primitives
import Schema
import TestFlows

private enum ProgramToolRecoveryMode:
    Sendable,
    Equatable
{
    case observe_retry
    case mutation_applied
    case mutation_applied_without_output
    case mutation_unknown
}

private enum ProgramToolRecoveryFixtureError:
    Error,
    LocalizedError,
    Equatable
{
    case transient
    case uncertain
    case unexpected_call

    var errorDescription: String? {
        switch self {
        case .transient:
            return "Fixture observe operation failed transiently."

        case .uncertain:
            return "Fixture Program mutation has an uncertain external outcome."

        case .unexpected_call:
            return "Fixture mutation was executed again after reconciliation proved it was applied."
        }
    }
}

private struct ProgramToolRecoveryInput:
    Sendable,
    Codable,
    JSONSchemaProviding
{
    static var jsonschema: JSONSchema {
        .object {}
    }
}

private struct ProgramToolRecoveryOutput:
    Sendable,
    Codable,
    Hashable
{
    let status: String
}

private struct ProgramToolRecoveryProbeSnapshot: Sendable {
    let calls: Int
    let reconciliations: Int
    let preflights: Int
}

private actor ProgramToolRecoveryProbe {
    private var calls = 0
    private var reconciliations = 0
    private var preflights = 0

    func recordCall() -> Int {
        calls += 1
        return calls
    }

    func recordReconciliation() {
        reconciliations += 1
    }

    func recordPreflight() {
        preflights += 1
    }

    func snapshot() -> ProgramToolRecoveryProbeSnapshot {
        ProgramToolRecoveryProbeSnapshot(
            calls: calls,
            reconciliations: reconciliations,
            preflights: preflights
        )
    }
}

private struct ProgramToolRecoveryFixtureTool: AgentTool {
    typealias Input = ProgramToolRecoveryInput
    typealias Output = ProgramToolRecoveryOutput

    let mode: ProgramToolRecoveryMode
    let probe: ProgramToolRecoveryProbe

    let identifier: AgentToolIdentifier =
        "fixture.program_tool_recovery"
    let description =
        "Exercises governed Program tool recovery."

    var risk: ActionRisk {
        switch mode {
        case .observe_retry:
            .observe

        case .mutation_applied,
             .mutation_applied_without_output,
             .mutation_unknown:
            .boundedmutate
        }
    }

    func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        _ = input
        _ = context
        await probe.recordPreflight()

        return ToolPreflight(
            toolName: identifier.rawValue,
            risk: risk,
            summary: "Program governed tool recovery fixture."
        )
    }

    func call(
        _ input: Input,
        context _: AgentToolExecutionContext
    ) async throws -> Output {
        _ = input
        let number = await probe.recordCall()

        switch mode {
        case .observe_retry:
            if number == 1 {
                throw ProgramToolRecoveryFixtureError.transient
            }

            return Output(
                status: "retried"
            )

        case .mutation_applied,
             .mutation_applied_without_output,
             .mutation_unknown:
            guard number == 1 else {
                throw ProgramToolRecoveryFixtureError.unexpected_call
            }

            throw ProgramToolRecoveryFixtureError.uncertain
        }
    }

    func classify(
        _ error: any Error,
        phase: AgentToolCallPhase,
        input _: Input?,
        context: AgentToolExecutionContext
    ) -> Recovery.Incident? {
        guard
            phase == .call,
            let error = error as? ProgramToolRecoveryFixtureError
        else {
            return nil
        }

        switch (mode, error) {
        case (.observe_retry, .transient):
            return Recovery.Incident(
                kind: .transport_transient,
                stage: .execution,
                effectState: .none,
                retrySafety: .safe,
                scope: .init(
                    kind: .tool,
                    identifier:
                        context.toolCallID
                        ?? identifier.rawValue
                ),
                message: "fixture observe operation failed before applying effects"
            )

        case (.mutation_applied, .uncertain),
             (.mutation_applied_without_output, .uncertain),
             (.mutation_unknown, .uncertain):
            return Recovery.Incident(
                kind: .outcome_unknown,
                stage: .execution,
                effectState: .unknown,
                retrySafety: .requires_reconciliation,
                scope: .init(
                    kind: .tool,
                    identifier:
                        context.toolCallID
                        ?? identifier.rawValue
                ),
                message: "fixture Program mutation outcome is unknown"
            )

        default:
            return nil
        }
    }

    func reconcile(
        _ input: Input,
        after failure: AgentToolCallFailure,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolReconciliation<Output>? {
        _ = input
        _ = context

        guard failure.phase == .call else {
            return nil
        }

        switch mode {
        case .observe_retry:
            return nil

        case .mutation_applied:
            await probe.recordReconciliation()

            return .applied(
                Output(
                    status: "reconciled"
                )
            )

        case .mutation_applied_without_output:
            await probe.recordReconciliation()
            return .applied_without_output

        case .mutation_unknown:
            await probe.recordReconciliation()
            return .unknown
        }
    }
}

private func programToolRecoveryPolicy() -> Recovery.Policy {
    Recovery.Policy(
        rules: [
            .init(
                match: .init(
                    kind: .transport_transient,
                    stage: .execution,
                    scope: .tool,
                    effectState: Recovery.EffectState.none,
                    retrySafety: .safe
                ),
                plan: .init(
                    steps: [
                        .init(
                            action: .retry_same_operation,
                            limit: .once
                        ),
                    ]
                )
            ),
            .init(
                match: .init(
                    kind: .outcome_unknown,
                    stage: .execution,
                    scope: .tool,
                    effectState: .unknown,
                    retrySafety: .requires_reconciliation
                ),
                plan: .init(
                    steps: [
                        .init(
                            action: .reconcile,
                            limit: .once
                        ),
                        .init(
                            action: .retry_same_operation,
                            limit: .once
                        ),
                    ]
                )
            ),
        ]
    )
}

private func runProgramToolRecovery(
    _ mode: ProgramToolRecoveryMode
) async throws -> (
    output: ProgramToolRecoveryOutput,
    recovery: Recovery.Record?,
    snapshot: ProgramToolRecoveryProbeSnapshot
) {
    let probe = ProgramToolRecoveryProbe()
    let tool = ProgramToolRecoveryFixtureTool(
        mode: mode,
        probe: probe
    )
    let registry = try ToolRegistry {
        tool
    }
    let executor = GovernedAgentProgramToolExecutor(
        registry: registry,
        policy: ToolExecutionPolicy(
            autonomyMode: .auto_bounded_mutate
        ),
        recovery: programToolRecoveryPolicy()
    )
    let execution = try await executor.invoke(
        tool.identifier,
        input: try JSONToolBridge.encode(
            ProgramToolRecoveryInput()
        )
    )

    return (
        output: try JSONToolBridge.decode(
            ProgramToolRecoveryOutput.self,
            from: execution.output
        ),
        recovery: execution.recovery,
        snapshot: await probe.snapshot()
    )
}

private func runProgramToolResumeRecovery()
    async throws
    -> (
        output: ProgramToolRecoveryOutput,
        recovery: Recovery.Record?,
        snapshot: ProgramToolRecoveryProbeSnapshot
    )
{
    let probe = ProgramToolRecoveryProbe()
    let tool = ProgramToolRecoveryFixtureTool(
        mode: .mutation_applied,
        probe: probe
    )
    let registry = try ToolRegistry {
        tool
    }
    let executor = GovernedAgentProgramToolExecutor(
        registry: registry,
        policy: ToolExecutionPolicy(
            autonomyMode: .auto_observe
        ),
        recovery: programToolRecoveryPolicy()
    )
    let call = AgentToolCall(
        id: "fixture-program-resume-recovery",
        name: tool.identifier.rawValue,
        input: try JSONToolBridge.encode(
            ProgramToolRecoveryInput()
        )
    )
    let review = try await executor.invoker.review(
        call,
        context: executor.context
    )

    try Expect.equal(
        review.requirement,
        .needs_human_review,
        "bounded Program mutation reaches approval under auto-observe"
    )

    let execution = try await executor.resume(
        pendingApproval: PendingApproval(
            toolCall: call,
            preflight: review.preflight,
            requirement: review.requirement
        ),
        decision: .approved
    )

    return (
        output: try JSONToolBridge.decode(
            ProgramToolRecoveryOutput.self,
            from: execution.output
        ),
        recovery: execution.recovery,
        snapshot: await probe.snapshot()
    )
}

private struct ProgramToolRecoveryProgram: AgentProgram {
    typealias Input = ProgramToolRecoveryInput
    typealias Output = ProgramToolRecoveryOutput

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.program_tool_recovery_program",
        title: "Program tool recovery evidence",
        summary: "Proves tool recovery evidence survives Program execution recording."
    )

    func run(
        _ input: Input,
        in context: AgentProgramContext
    ) async throws -> Output {
        try await context.invoke(
            "fixture.program_tool_recovery",
            input: input,
            as: Output.self
        )
    }
}

private func runRecordedProgramToolRecovery(
    _ mode: ProgramToolRecoveryMode
) async throws -> (
    execution: AgentProgramExecution<ProgramToolRecoveryProgram>,
    snapshot: ProgramToolRecoveryProbeSnapshot
) {
    let probe = ProgramToolRecoveryProbe()
    let tool = ProgramToolRecoveryFixtureTool(
        mode: mode,
        probe: probe
    )
    let registry = try ToolRegistry {
        tool
    }
    let executor = GovernedAgentProgramToolExecutor(
        registry: registry,
        policy: ToolExecutionPolicy(
            autonomyMode: .auto_bounded_mutate
        ),
        recovery: programToolRecoveryPolicy()
    )
    let runner = AgentProgramRunner(
        services: .init(
            program: .init(
                tools: executor
            )
        )
    )
    let execution = try await runner.execute(
        ProgramToolRecoveryProgram(),
        input: ProgramToolRecoveryInput()
    )

    return (
        execution: execution,
        snapshot: await probe.snapshot()
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runProgramGovernedToolRecovery()
        async throws
        -> [TestFlowDiagnostic]
    {
        let observe = try await runProgramToolRecovery(
            .observe_retry
        )
        let mutation = try await runProgramToolRecovery(
            .mutation_applied
        )
        let resumedMutation = try await runProgramToolResumeRecovery()
        let recordedObserve = try await runRecordedProgramToolRecovery(
            .observe_retry
        )
        let recordedMutation = try await runRecordedProgramToolRecovery(
            .mutation_applied
        )
        let recordedAppliedWithoutOutput = try await runRecordedProgramToolRecovery(
            .mutation_applied_without_output
        )
        let recordedUnknown = try await runRecordedProgramToolRecovery(
            .mutation_unknown
        )

        try Expect.equal(
            observe.output.status,
            "retried",
            "governed Program observe tool recovers by exact retry"
        )
        try Expect.equal(
            observe.snapshot.calls,
            2,
            "observe recovery performs exactly one bounded retry"
        )
        try Expect.equal(
            observe.snapshot.reconciliations,
            0,
            "safe observe recovery does not reconcile"
        )
        try Expect.equal(
            observe.snapshot.preflights,
            1,
            "observe exact retry does not require mutation re-preflight"
        )
        let observeRecovery = try Expect.notNil(
            observe.recovery,
            "governed Program observe retry returns its Recovery.Record"
        )
        try Expect.equal(
            observeRecovery.outcome,
            .recovered,
            "observe retry execution envelope preserves recovered outcome"
        )

        try Expect.equal(
            mutation.output.status,
            "reconciled",
            "governed Program mutation returns reconstructed reconciliation output"
        )
        try Expect.equal(
            mutation.snapshot.calls,
            1,
            "applied reconciliation never repeats the mutation"
        )
        try Expect.equal(
            mutation.snapshot.reconciliations,
            1,
            "uncertain Program mutation performs one reconciliation"
        )
        try Expect.equal(
            mutation.snapshot.preflights,
            1,
            "applied reconciliation needs no retry preflight"
        )
        let mutationRecovery = try Expect.notNil(
            mutation.recovery,
            "governed Program mutation returns its reconciliation record"
        )
        try Expect.equal(
            mutationRecovery.state,
            Recovery.State(
                reconciled: .applied
            ),
            "reconciled Program mutation exposes its applied state"
        )

        try Expect.equal(
            resumedMutation.output.status,
            "reconciled",
            "approved Program resume uses the same reconciliation substrate"
        )
        try Expect.equal(
            resumedMutation.snapshot.calls,
            1,
            "approval resume does not repeat an applied mutation"
        )
        try Expect.equal(
            resumedMutation.snapshot.reconciliations,
            1,
            "approval resume reconciles one uncertain mutation"
        )
        try Expect.equal(
            resumedMutation.snapshot.preflights,
            2,
            "approval resume performs original and stale-approval preflight reviews"
        )
        let resumedRecovery = try Expect.notNil(
            resumedMutation.recovery,
            "approval resume preserves its reconciliation record"
        )
        try Expect.equal(
            resumedRecovery.outcome,
            .recovered,
            "approval-resumed mutation reports recovered outcome"
        )

        let recordedObserveStep = try Expect.notNil(
            recordedObserve.execution.record.steps.first,
            "recorded observe Program retains its tool step"
        )
        let recordedObserveRecovery = try Expect.notNil(
            recordedObserveStep.recovery,
            "successful recovered Program tool step persists Recovery.Record"
        )
        try Expect.equal(
            recordedObserve.execution.record.outcome,
            .succeeded,
            "mechanically recovered observe tool preserves Program success"
        )
        try Expect.equal(
            recordedObserveRecovery.outcome,
            .recovered,
            "Program trace preserves recovered observe outcome"
        )

        let recordedMutationStep = try Expect.notNil(
            recordedMutation.execution.record.steps.first,
            "recorded reconciled mutation retains its tool step"
        )
        let recordedMutationRecovery = try Expect.notNil(
            recordedMutationStep.recovery,
            "successful reconciled mutation persists Recovery.Record"
        )
        try Expect.equal(
            recordedMutation.execution.record.outcome,
            .succeeded,
            "reconciliation with reconstructed output preserves Program success"
        )
        try Expect.equal(
            recordedMutationRecovery.state,
            Recovery.State(
                reconciled: .applied
            ),
            "Program trace preserves applied reconciliation state"
        )

        let appliedWithoutOutputStep = try Expect.notNil(
            recordedAppliedWithoutOutput.execution.record.steps.first,
            "applied-without-output failure retains its Program tool step"
        )
        let appliedWithoutOutputRecovery = try Expect.notNil(
            appliedWithoutOutputStep.recovery,
            "failed Program step retains applied-without-output recovery evidence"
        )
        try Expect.equal(
            recordedAppliedWithoutOutput.execution.record.outcome,
            .failed,
            "applied effect without typed output remains a failed Program operation"
        )
        try Expect.equal(
            appliedWithoutOutputStep.failure != nil,
            true,
            "applied-without-output remains an explicit failed Program step"
        )
        try Expect.equal(
            appliedWithoutOutputRecovery.outcome,
            .failed,
            "applied-without-output preserves failed whole-recovery outcome"
        )
        try Expect.equal(
            appliedWithoutOutputRecovery.state,
            Recovery.State(
                reconciled: .applied
            ),
            "failed Program operation still records that its external effect applied"
        )
        try Expect.equal(
            recordedAppliedWithoutOutput.snapshot.calls,
            1,
            "applied-without-output evidence never causes a blind mutation retry"
        )

        let unknownStep = try Expect.notNil(
            recordedUnknown.execution.record.steps.first,
            "unresolved mutation failure retains its Program tool step"
        )
        let unknownRecovery = try Expect.notNil(
            unknownStep.recovery,
            "unresolved Program mutation persists its Recovery.Record"
        )
        try Expect.equal(
            recordedUnknown.execution.record.outcome,
            .failed,
            "unresolved mutation remains a failed Program operation"
        )
        try Expect.equal(
            unknownRecovery.outcome,
            .exhausted,
            "Program trace preserves exhausted reconciliation outcome"
        )
        try Expect.equal(
            unknownRecovery.state,
            Recovery.State(
                reconciled: .unknown
            ),
            "Program trace preserves unresolved mutation state"
        )
        try Expect.equal(
            recordedUnknown.snapshot.calls,
            1,
            "unresolved Program mutation is never blindly retried"
        )

        return [
            .field(
                "observe_calls",
                String(observe.snapshot.calls)
            ),
            .field(
                "mutation_calls",
                String(mutation.snapshot.calls)
            ),
            .field(
                "mutation_reconciliations",
                String(mutation.snapshot.reconciliations)
            ),
            .field(
                "resume_mutation_calls",
                String(resumedMutation.snapshot.calls)
            ),
            .field(
                "resume_reconciliations",
                String(resumedMutation.snapshot.reconciliations)
            ),
            .field(
                "recorded_observe_recovery",
                recordedObserveRecovery.outcome.rawValue
            ),
            .field(
                "recorded_mutation_effect",
                recordedMutationRecovery.state.effect.rawValue
            ),
            .field(
                "applied_without_output_effect",
                appliedWithoutOutputRecovery.state.effect.rawValue
            ),
            .field(
                "unknown_recovery",
                unknownRecovery.outcome.rawValue
            ),
        ]
    }
}
