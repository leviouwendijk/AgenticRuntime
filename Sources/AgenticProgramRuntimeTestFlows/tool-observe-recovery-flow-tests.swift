import Agentic
import AgenticExecution
import AgenticRecovery
import AgenticRuntime
import Primitives
import Schema
import TestFlows

private enum ObserveRecoveryFixtureError: Error {
    case transient
}

private actor ObserveRecoveryProbe {
    private var calls = 0

    func recordCall() -> Int {
        calls += 1
        return calls
    }

    func count() -> Int {
        calls
    }
}

private struct ObserveRecoveryFixtureInput:
    Sendable,
    Codable,
    JSONSchemaProviding
{
    static var jsonschema: JSONSchema {
        .object {}
    }
}

private struct ObserveRecoveryFixtureTool: AgentTool {
    typealias Input = ObserveRecoveryFixtureInput
    typealias Output = JSONValue

    let identifier: AgentToolIdentifier =
        "fixture.observe_recovery"
    let description =
        "Observe-only fixture that fails transiently once before succeeding."
    let risk: ActionRisk = .observe
    let probe: ObserveRecoveryProbe

    func call(
        _ input: Input,
        context _: AgentToolExecutionContext
    ) async throws -> Output {
        _ = input

        let call = await probe.recordCall()

        guard call > 1 else {
            throw ObserveRecoveryFixtureError.transient
        }

        return .object([
            "status": .string("recovered")
        ])
    }

    func classify(
        _ error: any Error,
        phase: AgentToolCallPhase,
        input _: Input?,
        context: AgentToolExecutionContext
    ) -> Recovery.Incident? {
        guard
            phase == .call,
            error is ObserveRecoveryFixtureError
        else {
            return nil
        }

        return Recovery.Incident(
            kind: .transport_transient,
            stage: .execution,
            effectState: .not_applied,
            retrySafety: .safe,
            scope: .init(
                kind: .tool,
                identifier:
                    context.toolCallID
                    ?? identifier.rawValue
            ),
            message: "fixture observe operation failed before applying effects"
        )
    }
}

private actor ObserveRecoveryModelState {
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

private struct ObserveRecoveryModelInvoker: AgentModelInvoking {
    let state: ObserveRecoveryModelState
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
                    text: "observe recovery complete"
                ),
                stopReason: .end_turn
            )
        }

        let routeResult = AgentModelRouteResult(
            route: AgentModelRoute(
                purpose: invocation.selection.purpose,
                profile: AgentModelProfile(
                    identifier: "fixture.observe_recovery.profile",
                    gatewayIdentifier: "fixture.observe_recovery.gateway",
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

extension AgenticProgramRuntimeFlowTesting {
    static func runObserveToolRecovery()
        async throws
        -> [TestFlowDiagnostic]
    {
        let probe = ObserveRecoveryProbe()
        let state = ObserveRecoveryModelState()
        let toolCall = AgentToolCall(
            id: "fixture-observe-recovery-call",
            name: "fixture.observe_recovery",
            input: try JSONToolBridge.encode(
                ObserveRecoveryFixtureInput()
            )
        )
        let policy = Recovery.Policy(
            rules: [
                .init(
                    match: .init(
                        kind: .transport_transient,
                        stage: .execution,
                        scope: .tool,
                        effectState: .not_applied,
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
            ]
        )
        let registry = try ToolRegistry {
            ObserveRecoveryFixtureTool(
                probe: probe
            )
        }
        let runner = AgentRunner(
            model: .init(
                invoker: ObserveRecoveryModelInvoker(
                    state: state,
                    toolCall: toolCall
                )
            ),
            configuration: .init(
                maximumIterations: 2,
                recovery: policy
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
                        text: "Exercise safe observe recovery."
                    ),
                ]
            ),
            sessionID: "fixture-observe-recovery"
        )
        let calls = await probe.count()
        let invocations = await state.snapshot()
        let toolUse = try Expect.notNil(
            result.toolUses.first,
            "recovered observe call has a durable tool-use record"
        )
        let recovery = try Expect.notNil(
            toolUse.recovery,
            "recovered observe call persists its recovery record"
        )

        try Expect.equal(
            calls,
            2,
            "observe tool executes once initially and once as its bounded recovery attempt"
        )
        try Expect.equal(
            recovery.outcome,
            .recovered,
            "observe recovery record is terminally recovered"
        )
        try Expect.equal(
            recovery.attempts.count,
            1,
            "one bounded retry is recorded as one recovery attempt"
        )
        let recoveryAttempt = try Expect.notNil(
            recovery.attempts.first,
            "observe recovery records its retry attempt"
        )
        let recoveryState = try Expect.notNil(
            recoveryAttempt.state,
            "successful observe retry records its established state"
        )

        try Expect.equal(
            recoveryAttempt.status,
            .succeeded,
            "successful exact retry is a succeeded recovery action"
        )
        try Expect.equal(
            recoveryState,
            Recovery.State(
                reconciled: .none
            ),
            "successful observe retry leaves no external mutation effect"
        )
        try Expect.equal(
            recovery.state,
            recoveryState,
            "recovery record exposes the authoritative successful observe state"
        )
        try Expect.equal(
            recovery.incident.kind,
            .transport_transient,
            "tool-local classifier preserves the normalized incident kind"
        )
        _ = try Expect.notNil(
            recovery.incident.report,
            "observe recovery record preserves structured evidence from the initial execution failure"
        )
        try Expect.equal(
            toolUse.result?.isError,
            false,
            "the model-facing terminal tool result is the recovered success"
        )
        try Expect.equal(
            invocations.count,
            2,
            "tool recovery does not create an extra model turn"
        )

        let terminalResults = invocations[1].request.messages
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
            terminalResults.count,
            1,
            "one model toolUse receives exactly one terminal toolResult despite internal retry"
        )
        try Expect.equal(
            terminalResults[0].isError,
            false,
            "intermediate recovery failure never becomes a model-facing error result"
        )

        return [
            .field(
                "tool_calls",
                String(calls)
            ),
            .field(
                "recovery_attempts",
                String(recovery.attempts.count)
            ),
            .field(
                "terminal_results",
                String(terminalResults.count)
            ),
            .field(
                "recovery_outcome",
                recovery.outcome.rawValue
            ),
            .field(
                "incident_report",
                String(recovery.incident.report != nil)
            ),
        ]
    }
}
