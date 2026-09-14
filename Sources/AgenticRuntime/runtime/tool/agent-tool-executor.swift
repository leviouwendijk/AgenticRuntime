import Agentic
import AgenticExecution
import AgenticRecovery
import Foundation
import Primitives

struct AgentToolExecutor {
    let invoker: ToolInvoker
    let recovery: Recovery.Policy?
    let context: AgentToolExecutionContext

    func execute(
        _ call: AgentToolCall,
        preflight: ToolPreflight
    ) async throws -> AgentToolExecutionResult {
        do {
            return AgentToolExecutionResult(
                result: try await invoker.registry.execute(
                    call,
                    context: context
                ),
                recovery: nil
            )
        } catch {
            let propagatedRecovery: Recovery.Record?

            if let toolError = error as? AgentToolCallError,
               let incident = toolError.failure.incident
            {
                propagatedRecovery = Recovery.Record(
                    incident: incident,
                    plan: nil,
                    attempts: [],
                    outcome: .propagated
                )
            } else {
                propagatedRecovery = nil
            }

            guard var recovery = AgentToolExecutorActiveRecovery(
                error: error,
                policy: recovery
            ) else {
                return AgentToolExecutionResult(
                    result: try makeErrorResult(
                        for: call,
                        error: error
                    ),
                    recovery: propagatedRecovery
                )
            }

            while let decision = recovery.decision {
                guard AgentToolExecutorActiveRecovery.allows(
                    decision.action,
                    state: recovery.state
                ) else {
                    let recoveryError =
                        AgentToolExecutorError.action_unsupported(
                            decision.action
                        )

                    return AgentToolExecutionResult(
                        result: try makeErrorResult(
                            for: call,
                            error: recoveryError
                        ),
                        recovery: recovery.record(
                            outcome: .failed
                        )
                    )
                }

                guard let permit = decision.limit.nextAttempt(
                    after: recovery.completedAttemptsInStep
                ) else {
                    let recoveryError =
                        AgentToolExecutorError.recovery_exhausted

                    return AgentToolExecutionResult(
                        result: try makeErrorResult(
                            for: call,
                            error: recoveryError
                        ),
                        recovery: recovery.record(
                            outcome: .exhausted
                        )
                    )
                }

                recovery.completedAttemptsInStep += 1

                switch decision.action {
                case .reconcile:
                    do {
                        guard let reconciliation = try await invoker.registry.reconcile(
                            call,
                            failure: recovery.failure,
                            context: context
                        ) else {
                            let recoveryError =
                                AgentToolExecutorError
                                    .reconciliation_unsupported

                            recovery.attempts.append(
                                Recovery.Attempt(
                                    capturing: recoveryError,
                                    number: permit.number,
                                    action: decision.action,
                                    state: recovery.state
                                )
                            )

                            return AgentToolExecutionResult(
                                result: try makeErrorResult(
                                    for: call,
                                    error: recoveryError
                                ),
                                recovery: recovery.record(
                                    outcome: .failed
                                )
                            )
                        }

                        let state = reconciliation.state

                        recovery.attempts.append(
                            Recovery.Attempt(
                                number: permit.number,
                                action: decision.action,
                                status: .succeeded,
                                state: state
                            )
                        )
                        recovery.state = state

                        switch reconciliation {
                        case .applied(let result):
                            return AgentToolExecutionResult(
                                result: result,
                                recovery: recovery.record(
                                    outcome: .recovered
                                )
                            )

                        case .applied_without_output:
                            let recoveryError =
                                AgentToolExecutorError
                                    .applied_without_output

                            return AgentToolExecutionResult(
                                result: try makeErrorResult(
                                    for: call,
                                    error: recoveryError
                                ),
                                recovery: recovery.record(
                                    outcome: .failed
                                )
                            )

                        case .not_applied:
                            recovery.advance(
                                to: state
                            )
                            continue

                        case .unknown:
                            guard decision.limit.nextAttempt(
                                after: recovery.completedAttemptsInStep
                            ) == nil else {
                                continue
                            }

                            let recoveryError =
                                AgentToolExecutorError
                                    .reconciliation_unresolved

                            return AgentToolExecutionResult(
                                result: try makeErrorResult(
                                    for: call,
                                    error: recoveryError
                                ),
                                recovery: recovery.record(
                                    outcome: .exhausted
                                )
                            )
                        }
                    } catch {
                        recovery.attempts.append(
                            Recovery.Attempt(
                                capturing: error,
                                number: permit.number,
                                action: decision.action,
                                state: recovery.state
                            )
                        )

                        guard decision.limit.nextAttempt(
                            after: recovery.completedAttemptsInStep
                        ) == nil else {
                            continue
                        }

                        return AgentToolExecutionResult(
                            result: try makeErrorResult(
                                for: call,
                                error: error
                            ),
                            recovery: recovery.record(
                                outcome: .exhausted
                            )
                        )
                    }

                case .retry_same_operation:
                    if preflight.risk.isMutating {
                        do {
                            let refreshed = try await invoker.review(
                                call,
                                context: context
                            ).preflight

                            guard refreshed == preflight else {
                                let recoveryError =
                                    AgentToolExecutorError
                                        .preflight_changed

                                recovery.attempts.append(
                                    Recovery.Attempt(
                                        capturing: recoveryError,
                                        number: permit.number,
                                        action: decision.action,
                                        state: recovery.state
                                    )
                                )

                                return AgentToolExecutionResult(
                                    result: try makeErrorResult(
                                        for: call,
                                        error: recoveryError
                                    ),
                                    recovery: recovery.record(
                                        outcome: .failed
                                    )
                                )
                            }
                        } catch {
                            recovery.attempts.append(
                                Recovery.Attempt(
                                    capturing: error,
                                    number: permit.number,
                                    action: decision.action,
                                    state: recovery.state
                                )
                            )

                            return AgentToolExecutionResult(
                                result: try makeErrorResult(
                                    for: call,
                                    error: error
                                ),
                                recovery: recovery.record(
                                    outcome: .failed
                                )
                            )
                        }
                    }

                    do {
                        let result = try await invoker.registry.execute(
                            call,
                            context: context
                        )
                        let state = Recovery.State(
                            reconciled:
                                preflight.risk.isMutating
                                ? .applied
                                : .none
                        )

                        recovery.state = state
                        recovery.attempts.append(
                            Recovery.Attempt(
                                number: permit.number,
                                action: decision.action,
                                status: .succeeded,
                                state: state
                            )
                        )

                        return AgentToolExecutionResult(
                            result: result,
                            recovery: recovery.record(
                                outcome: .recovered
                            )
                        )
                    } catch {
                        let accepted = recovery.absorb(
                            error
                        )

                        recovery.attempts.append(
                            Recovery.Attempt(
                                capturing: error,
                                number: permit.number,
                                action: decision.action,
                                state: recovery.state
                            )
                        )

                        guard accepted else {
                            return AgentToolExecutionResult(
                                result: try makeErrorResult(
                                    for: call,
                                    error: error
                                ),
                                recovery: recovery.record(
                                    outcome: .failed
                                )
                            )
                        }

                        guard AgentToolExecutorActiveRecovery.allows(
                            decision.action,
                            state: recovery.state
                        ) else {
                            return AgentToolExecutionResult(
                                result: try makeErrorResult(
                                    for: call,
                                    error: error
                                ),
                                recovery: recovery.record(
                                    outcome: .failed
                                )
                            )
                        }

                        guard decision.limit.nextAttempt(
                            after: recovery.completedAttemptsInStep
                        ) == nil else {
                            continue
                        }

                        return AgentToolExecutionResult(
                            result: try makeErrorResult(
                                for: call,
                                error: error
                            ),
                            recovery: recovery.record(
                                outcome: .exhausted
                            )
                        )
                    }

                default:
                    let recoveryError =
                        AgentToolExecutorError.action_unsupported(
                            decision.action
                        )

                    recovery.attempts.append(
                        Recovery.Attempt(
                            capturing: recoveryError,
                            number: permit.number,
                            action: decision.action,
                            state: recovery.state
                        )
                    )

                    return AgentToolExecutionResult(
                        result: try makeErrorResult(
                            for: call,
                            error: recoveryError
                        ),
                        recovery: recovery.record(
                            outcome: .failed
                        )
                    )
                }
            }

            let recoveryError =
                AgentToolExecutorError.recovery_exhausted

            return AgentToolExecutionResult(
                result: try makeErrorResult(
                    for: call,
                    error: recoveryError
                ),
                recovery: recovery.record(
                    outcome: .exhausted
                )
            )
        }
    }

    private func makeErrorResult(
        for call: AgentToolCall,
        error: any Error
    ) throws -> AgentToolResult {
        let payload = AgentToolExecutorErrorPayload(
            kind: "tool_error",
            toolCallID: call.id,
            toolName: call.name,
            message: localizedDescription(
                for: error
            )
        )

        return AgentToolResult(
            toolCallID: call.id,
            name: call.name,
            output: try JSONToolBridge.encode(
                payload
            ),
            isError: true
        )
    }

    private func localizedDescription(
        for error: any Error
    ) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty
        {
            return description
        }

        return String(
            describing: error
        )
    }
}

private enum AgentToolExecutorError:
    Error,
    LocalizedError
{
    case reconciliation_unsupported
    case reconciliation_unresolved
    case applied_without_output
    case preflight_changed
    case recovery_exhausted
    case action_unsupported(Recovery.Action)

    var errorDescription: String? {
        switch self {
        case .reconciliation_unsupported:
            return "Tool does not support reconciliation for the classified failure."

        case .reconciliation_unresolved:
            return "Tool reconciliation could not determine whether the operation was applied."

        case .applied_without_output:
            return "Tool reconciliation confirmed the operation was applied but could not reconstruct the tool output."

        case .preflight_changed:
            return "Tool preflight changed after reconciliation; retry requires fresh approval."

        case .recovery_exhausted:
            return "Tool recovery exhausted its authored mechanical recovery plan."

        case .action_unsupported(let action):
            return "Runtime does not mechanically execute recovery action '\(action.rawValue)'."
        }
    }
}

private struct AgentToolExecutorActiveRecovery {
    let incident: Recovery.Incident
    let plan: Recovery.Plan
    var failure: AgentToolCallFailure
    var attempts: [Recovery.Attempt]
    var state: Recovery.State
    var stepIndex: Int
    var completedAttemptsInStep: UInt

    init?(
        error: any Error,
        policy: Recovery.Policy?
    ) {
        guard
            let error = error as? AgentToolCallError,
            error.failure.phase == .call,
            let incident = error.failure.incident,
            let plan = policy?.plan(
                for: incident
            ),
            let first = plan.steps.first,
            Self.allows(
                first.action,
                state: incident.state
            )
        else {
            return nil
        }

        self.incident = incident
        self.plan = plan
        self.failure = error.failure
        self.attempts = []
        self.state = incident.state
        self.stepIndex = 0
        self.completedAttemptsInStep = 0
    }

    var decision: Recovery.Decision? {
        guard plan.steps.indices.contains(stepIndex) else {
            return nil
        }

        return Recovery.Decision(
            step: plan.steps[stepIndex]
        )
    }

    mutating func advance(
        to state: Recovery.State
    ) {
        self.state = state
        stepIndex += 1
        completedAttemptsInStep = 0
    }

    mutating func absorb(
        _ error: any Error
    ) -> Bool {
        guard
            let error = error as? AgentToolCallError,
            error.failure.phase == .call,
            let incident = error.failure.incident,
            incident.kind == self.incident.kind,
            incident.stage == self.incident.stage,
            incident.scope == self.incident.scope
        else {
            return false
        }

        failure = error.failure
        state = incident.state
        return true
    }

    func record(
        outcome: Recovery.Outcome
    ) -> Recovery.Record {
        Recovery.Record(
            incident: incident,
            plan: plan,
            attempts: attempts,
            state: state,
            outcome: outcome
        )
    }

    static func allows(
        _ action: Recovery.Action,
        state: Recovery.State
    ) -> Bool {
        switch action {
        case .reconcile:
            return state.effect == .unknown
                && state.retry == .requires_reconciliation

        case .retry_same_operation:
            return state.retry == .safe
                && (
                    state.effect == .none
                    || state.effect == .not_applied
                )

        default:
            return false
        }
    }
}

private struct AgentToolExecutorErrorPayload:
    Encodable,
    Sendable
{
    let kind: String
    let toolCallID: String
    let toolName: String
    let message: String
}
