import Foundation
import Agentic
import AgenticExecution
import AgenticRecovery
import AgenticRuntime
import Primitives
import Schema
import TestFlows

private enum ProgramToolRecoveryMode:
    Sendable,
    Equatable
{
    case observe_retry
    case mutation_applied
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

        case .mutation_applied:
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

        case .mutation_applied:
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

        case (.mutation_applied, .uncertain):
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

        guard
            mode == .mutation_applied,
            failure.phase == .call
        else {
            return nil
        }

        await probe.recordReconciliation()

        return .applied(
            Output(
                status: "reconciled"
            )
        )
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
    let output = try await executor.invoke(
        tool.identifier,
        input: try JSONToolBridge.encode(
            ProgramToolRecoveryInput()
        )
    )

    return (
        output: try JSONToolBridge.decode(
            ProgramToolRecoveryOutput.self,
            from: output
        ),
        snapshot: await probe.snapshot()
    )
}

private func runProgramToolResumeRecovery()
    async throws
    -> (
        output: ProgramToolRecoveryOutput,
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

    let output = try await executor.resume(
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
            from: output
        ),
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
        ]
    }
}
