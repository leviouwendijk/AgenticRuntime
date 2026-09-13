import Agentic
import AgenticExecution
import AgenticRecovery
import AgenticRuntime
import Foundation
import Primitives
import Schema
import TestFlows

private enum MutationRecoveryFixtureMode:
    String,
    Sendable
{
    case applied
    case applied_without_output
    case not_applied
    case unknown
}

private enum MutationRecoveryFixtureError:
    Error,
    LocalizedError,
    Equatable
{
    case uncertain
    case unexpected_call
    case invalid_failure

    var errorDescription: String? {
        switch self {
        case .uncertain:
            return "Fixture mutation failed with an uncertain external outcome."

        case .unexpected_call:
            return "Fixture mutation was executed again when retry was not permitted."

        case .invalid_failure:
            return "Fixture reconciliation received a non-call failure."
        }
    }
}

private struct MutationRecoveryFixtureInput:
    Sendable,
    Codable,
    JSONSchemaProviding
{
    static var jsonschema: JSONSchema {
        .object {}
    }
}

private struct MutationRecoveryFixtureOutput:
    Sendable,
    Codable,
    Hashable
{
    let status: String
}

private struct MutationRecoveryProbeSnapshot: Sendable {
    let calls: Int
    let reconciliations: Int
    let preflights: Int
}

private actor MutationRecoveryProbe {
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

    func snapshot() -> MutationRecoveryProbeSnapshot {
        MutationRecoveryProbeSnapshot(
            calls: calls,
            reconciliations: reconciliations,
            preflights: preflights
        )
    }
}

private struct MutationRecoveryFixtureTool: AgentTool {
    typealias Input = MutationRecoveryFixtureInput
    typealias Output = MutationRecoveryFixtureOutput

    let mode: MutationRecoveryFixtureMode
    let probe: MutationRecoveryProbe

    let identifier: AgentToolIdentifier =
        "fixture.mutation_recovery"
    let description =
        "Bounded mutation fixture for uncertain-outcome reconciliation."
    let risk: ActionRisk = .boundedmutate

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
            summary: "Fixture mutation recovery."
        )
    }

    func call(
        _ input: Input,
        context _: AgentToolExecutionContext
    ) async throws -> Output {
        _ = input
        let call = await probe.recordCall()

        if call == 1 {
            throw MutationRecoveryFixtureError.uncertain
        }

        guard
            mode == .not_applied,
            call == 2
        else {
            throw MutationRecoveryFixtureError.unexpected_call
        }

        return Output(
            status: "retried"
        )
    }

    func classify(
        _ error: any Error,
        phase: AgentToolCallPhase,
        input _: Input?,
        context: AgentToolExecutionContext
    ) -> Recovery.Incident? {
        guard
            phase == .call,
            let error = error as? MutationRecoveryFixtureError,
            error == .uncertain
        else {
            return nil
        }

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
            message: "fixture mutation outcome is unknown"
        )
    }

    func reconcile(
        _ input: Input,
        after failure: AgentToolCallFailure,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolReconciliation<Output>? {
        _ = input
        _ = context

        guard failure.phase == .call else {
            throw MutationRecoveryFixtureError.invalid_failure
        }

        await probe.recordReconciliation()

        switch mode {
        case .applied:
            return .applied(
                Output(
                    status: "reconciled"
                )
            )

        case .applied_without_output:
            return .applied_without_output

        case .not_applied:
            return .not_applied

        case .unknown:
            return .unknown
        }
    }
}

private actor MutationRecoveryModelState {
    private var invocations: [AgentModelInvocation] = []

    func record(
        _ invocation: AgentModelInvocation
    ) -> Int {
        let index = invocations.count
        invocations.append(
            invocation
        )
        return index
    }

    func snapshot() -> [AgentModelInvocation] {
        invocations
    }
}

private struct MutationRecoveryModelInvoker: AgentModelInvoking {
    let state: MutationRecoveryModelState
    let toolCall: AgentToolCall

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocationResult {
        let index = await state.record(
            invocation
        )
        let response: AgentResponse

        if index == 0 {
            response = AgentResponse(
                message: AgentMessage(
                    role: .assistant,
                    content: AgentContent(
                        blocks: [
                            .tool_call(toolCall),
                        ]
                    )
                ),
                stopReason: .tool_use
            )
        } else {
            response = AgentResponse(
                message: AgentMessage(
                    role: .assistant,
                    text: "mutation recovery complete"
                ),
                stopReason: .end_turn
            )
        }

        let routeResult = AgentModelRouteResult(
            route: AgentModelRoute(
                purpose: invocation.selection.purpose,
                profile: AgentModelProfile(
                    identifier: "fixture.mutation_recovery.profile",
                    gatewayIdentifier: "fixture.mutation_recovery.gateway",
                    model: "fixture",
                    purposes: [
                        invocation.selection.purpose,
                    ],
                    capabilities: [
                        .text,
                        .reasoning,
                    ]
                )
            )
        )

        return AgentModelInvocationResult(
            response: response,
            route: AgentModelRouteRecord(
                route: routeResult.route,
                diagnostics: routeResult.diagnostics,
                requestMetadata: invocation.request.metadata,
                responseMetadata: response.metadata,
                usage: response.usage
            )
        )
    }

    func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<AgentModelInvocationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await buffered(
                        invocation
                    )
                    continuation.yield(
                        .completed(result)
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: error
                    )
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private struct MutationRecoveryCaseResult {
    let probe: MutationRecoveryProbeSnapshot
    let result: AgentToolResult
    let recovery: Recovery.Record
}

private func mutationRecoveryPolicy() -> Recovery.Policy {
    Recovery.Policy(
        rules: [
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

private func runMutationRecoveryCase(
    _ mode: MutationRecoveryFixtureMode
) async throws -> MutationRecoveryCaseResult {
    let probe = MutationRecoveryProbe()
    let state = MutationRecoveryModelState()
    let toolCall = AgentToolCall(
        id: "fixture-mutation-recovery-\(mode.rawValue)",
        name: "fixture.mutation_recovery",
        input: try JSONToolBridge.encode(
            MutationRecoveryFixtureInput()
        )
    )
    let registry = try ToolRegistry {
        MutationRecoveryFixtureTool(
            mode: mode,
            probe: probe
        )
    }
    let runner = AgentRunner(
        model: .init(
            invoker: MutationRecoveryModelInvoker(
                state: state,
                toolCall: toolCall
            )
        ),
        configuration: .init(
            maximumIterations: 2,
            autonomyMode: .auto_bounded_mutate,
            recovery: mutationRecoveryPolicy()
        ),
        tooling: .init(
            registry: registry
        )
    )

    let result = try await runner.run(
        AgentRequest(
            messages: [
                AgentMessage(
                    role: .user,
                    text: "Exercise uncertain mutation recovery."
                ),
            ]
        ),
        sessionID: "fixture-mutation-recovery-\(mode.rawValue)"
    )
    let invocations = await state.snapshot()
    let toolUse = try Expect.notNil(
        result.toolUses.first,
        "mutation recovery produces a durable tool-use record"
    )
    let terminalResult = try Expect.notNil(
        toolUse.result,
        "mutation recovery produces one terminal tool result"
    )
    let recovery = try Expect.notNil(
        toolUse.recovery,
        "mutation recovery persists its Recovery.Record"
    )
    let secondInvocation = try Expect.notNil(
        invocations.dropFirst().first,
        "mutation recovery continues to exactly one terminal model turn"
    )
    let terminalResults = secondInvocation.request.messages
        .flatMap(\.content.blocks)
        .compactMap { block -> AgentToolResult? in
            guard case .tool_result(let result) = block else {
                return nil
            }

            return result
        }
        .filter { result in
            result.toolCallID == toolCall.id
        }

    try Expect.equal(
        invocations.count,
        2,
        "internal mutation recovery never creates an extra model turn"
    )
    try Expect.equal(
        terminalResults.count,
        1,
        "one model tool use receives exactly one terminal tool result"
    )

    return MutationRecoveryCaseResult(
        probe: await probe.snapshot(),
        result: terminalResult,
        recovery: recovery
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runMutationToolRecovery()
        async throws
        -> [TestFlowDiagnostic]
    {
        let applied = try await runMutationRecoveryCase(
            .applied
        )
        let appliedWithoutOutput = try await runMutationRecoveryCase(
            .applied_without_output
        )
        let notApplied = try await runMutationRecoveryCase(
            .not_applied
        )
        let unknown = try await runMutationRecoveryCase(
            .unknown
        )

        try Expect.equal(
            applied.probe.calls,
            1,
            "reconciliation proving applied never repeats the mutation"
        )
        try Expect.equal(
            applied.probe.reconciliations,
            1,
            "applied outcome performs one reconciliation"
        )
        try Expect.equal(
            applied.probe.preflights,
            1,
            "applied outcome needs only the original preflight"
        )
        try Expect.equal(
            applied.result.isError,
            false,
            "reconciliation with reconstructed output becomes terminal success"
        )
        try Expect.equal(
            applied.recovery.outcome,
            .recovered,
            "applied reconciliation recovers the operation"
        )
        try Expect.equal(
            applied.recovery.state,
            Recovery.State(
                reconciled: .applied
            ),
            "applied reconciliation leaves applied unsafe state"
        )
        try Expect.equal(
            applied.recovery.attempts.count,
            1,
            "applied reconciliation records one recovery action"
        )
        let appliedAttempt = try Expect.notNil(
            applied.recovery.attempts.first,
            "applied reconciliation records its attempt"
        )
        let appliedAttemptState = try Expect.notNil(
            appliedAttempt.state,
            "applied reconciliation records established state"
        )

        try Expect.equal(
            appliedAttempt.action,
            .reconcile,
            "applied recovery action is reconciliation"
        )
        try Expect.equal(
            appliedAttempt.status,
            .succeeded,
            "successful reconciliation is distinct from whole-recovery outcome"
        )
        try Expect.equal(
            appliedAttemptState,
            applied.recovery.state,
            "applied attempt state matches authoritative final state"
        )

        try Expect.equal(
            appliedWithoutOutput.probe.calls,
            1,
            "applied-without-output never repeats the mutation"
        )
        try Expect.equal(
            appliedWithoutOutput.probe.reconciliations,
            1,
            "applied-without-output reconciles once"
        )
        try Expect.equal(
            appliedWithoutOutput.probe.preflights,
            1,
            "applied-without-output does not enter retry preflight"
        )
        try Expect.equal(
            appliedWithoutOutput.result.isError,
            true,
            "applied state without reconstructable output remains model-facing failure"
        )
        try Expect.equal(
            appliedWithoutOutput.recovery.outcome,
            .failed,
            "reconciliation action may succeed while whole recovery fails"
        )
        try Expect.equal(
            appliedWithoutOutput.recovery.state,
            Recovery.State(
                reconciled: .applied
            ),
            "applied-without-output still records the mutation as definitely applied"
        )
        let appliedWithoutOutputAttempt = try Expect.notNil(
            appliedWithoutOutput.recovery.attempts.first,
            "applied-without-output records reconciliation"
        )

        try Expect.equal(
            appliedWithoutOutputAttempt.status,
            .succeeded,
            "reconciliation itself succeeded despite missing output"
        )

        try Expect.equal(
            notApplied.probe.calls,
            2,
            "not-applied reconciliation permits exactly one subsequent mutation retry"
        )
        try Expect.equal(
            notApplied.probe.reconciliations,
            1,
            "not-applied path reconciles before retry"
        )
        try Expect.equal(
            notApplied.probe.preflights,
            2,
            "mutation retry requires a fresh identical preflight"
        )
        try Expect.equal(
            notApplied.result.isError,
            false,
            "safe exact mutation retry returns terminal success"
        )
        try Expect.equal(
            notApplied.recovery.outcome,
            .recovered,
            "not-applied followed by successful exact retry recovers"
        )
        try Expect.equal(
            notApplied.recovery.attempts.count,
            2,
            "reconciliation and retry remain separate recovery attempts"
        )
        let notAppliedReconciliation = try Expect.notNil(
            notApplied.recovery.attempts.first,
            "not-applied path records reconciliation"
        )
        let notAppliedRetry = try Expect.notNil(
            notApplied.recovery.attempts.dropFirst().first,
            "not-applied path records exact retry"
        )
        let notAppliedState = try Expect.notNil(
            notAppliedReconciliation.state,
            "not-applied reconciliation records safe retry state"
        )
        let retriedState = try Expect.notNil(
            notAppliedRetry.state,
            "successful mutation retry records applied state"
        )

        try Expect.equal(
            notAppliedReconciliation.action,
            .reconcile,
            "first recovery action is reconciliation"
        )
        try Expect.equal(
            notAppliedReconciliation.status,
            .succeeded,
            "not-applied reconciliation succeeds"
        )
        try Expect.equal(
            notAppliedState,
            Recovery.State(
                reconciled: .not_applied
            ),
            "reconciliation proving non-application makes exact retry mechanically safe"
        )
        try Expect.equal(
            notAppliedRetry.action,
            .retry_same_operation,
            "second recovery action is exact retry"
        )
        try Expect.equal(
            notAppliedRetry.status,
            .succeeded,
            "exact mutation retry succeeds"
        )
        try Expect.equal(
            retriedState,
            Recovery.State(
                reconciled: .applied
            ),
            "successful mutation retry establishes applied unsafe state"
        )
        try Expect.equal(
            notApplied.recovery.state,
            retriedState,
            "record exposes applied state after successful retry"
        )

        try Expect.equal(
            unknown.probe.calls,
            1,
            "unresolved reconciliation never blindly repeats the mutation"
        )
        try Expect.equal(
            unknown.probe.reconciliations,
            1,
            "unknown outcome uses its bounded reconciliation attempt"
        )
        try Expect.equal(
            unknown.probe.preflights,
            1,
            "unknown reconciliation never reaches retry preflight"
        )
        try Expect.equal(
            unknown.result.isError,
            true,
            "unresolved mutation outcome remains model-facing failure"
        )
        try Expect.equal(
            unknown.recovery.outcome,
            .exhausted,
            "bounded unresolved reconciliation exhausts rather than retrying"
        )
        try Expect.equal(
            unknown.recovery.state,
            Recovery.State(
                reconciled: .unknown
            ),
            "unresolved recovery remains explicitly reconciliation-required"
        )
        let unknownAttempt = try Expect.notNil(
            unknown.recovery.attempts.first,
            "unknown path records reconciliation action"
        )
        let unknownState = try Expect.notNil(
            unknownAttempt.state,
            "unknown reconciliation records unresolved state"
        )

        try Expect.equal(
            unknownAttempt.action,
            .reconcile,
            "unknown path attempted reconciliation"
        )
        try Expect.equal(
            unknownAttempt.status,
            .succeeded,
            "reconciliation action can succeed while certainty remains unknown"
        )
        try Expect.equal(
            unknownState,
            unknown.recovery.state,
            "unknown attempt state remains authoritative"
        )

        return [
            .field(
                "applied_calls",
                String(applied.probe.calls)
            ),
            .field(
                "applied_without_output_error",
                String(appliedWithoutOutput.result.isError)
            ),
            .field(
                "not_applied_calls",
                String(notApplied.probe.calls)
            ),
            .field(
                "not_applied_preflights",
                String(notApplied.probe.preflights)
            ),
            .field(
                "unknown_calls",
                String(unknown.probe.calls)
            ),
            .field(
                "unknown_retry",
                unknown.recovery.state.retry.rawValue
            ),
        ]
    }
}
