import Agentic
import AgenticExecution
import AgenticPrograms
import AgenticRecovery
import Foundation
import Primitives

public enum AgentProgramToolGovernanceError:
    Error,
    Sendable,
    LocalizedError
{
    case needs_human_review(AgentToolIdentifier)
    case denied(AgentToolIdentifier)
    case skipped(AgentToolIdentifier)
    case stale_approval(AgentToolIdentifier)

    public var errorDescription: String? {
        switch self {
        case .needs_human_review(let identifier):
            return "Program tool '\(identifier.rawValue)' requires human review before execution."

        case .denied(let identifier):
            return "Program tool '\(identifier.rawValue)' was denied by execution policy or approval."

        case .skipped(let identifier):
            return "Program tool '\(identifier.rawValue)' was skipped by approval handling."

        case .stale_approval(let identifier):
            return "Program tool '\(identifier.rawValue)' changed since approval was requested; the stale approval was not executed."
        }
    }
}

/// Bridges an authored AgentProgram tool request into AgenticExecution's
/// canonical governed invocation path.
///
/// The Program identifies the semantic operation it needs. It does not receive
/// authority to execute that operation directly. Runtime owns Program approval,
/// suspension, and resume semantics while ToolInvoker owns review and canonical
/// mechanical execution.
public struct GovernedAgentProgramToolExecutor:
    AgentProgramToolExecuting,
    Sendable
{
    public let invoker: ToolInvoker
    public let context: AgentToolExecutionContext
    public let approvalHandler: (any ToolApprovalHandler)?

    public init(
        registry: ToolRegistry,
        policy: ToolExecutionPolicy,
        recovery: Recovery.Policy? = nil,
        context: AgentToolExecutionContext = .init(),
        approvalHandler: (any ToolApprovalHandler)? = nil
    ) {
        self.init(
            invoker: ToolInvoker(
                registry: registry,
                policy: policy,
                recovery: recovery
            ),
            context: context,
            approvalHandler: approvalHandler
        )
    }

    public init(
        invoker: ToolInvoker,
        context: AgentToolExecutionContext = .init(),
        approvalHandler: (any ToolApprovalHandler)? = nil
    ) {
        self.invoker = invoker
        self.context = context
        self.approvalHandler = approvalHandler
    }

    public func invoke(
        _ identifier: AgentToolIdentifier,
        input: JSONValue
    ) async throws -> AgentToolExecutionResult {
        let call = AgentToolCall(
            id: "program-\(UUID().uuidString)",
            name: identifier.rawValue,
            input: input
        )
        let review = try await invoker.review(
            call,
            context: context
        )
        let decision: ApprovalDecision

        switch review.requirement {
        case .no_approval_needed:
            decision = .approved

        case .needs_human_review:
            if let approvalHandler {
                decision = try await approvalHandler.decide(
                    on: review
                )
            } else {
                decision = .needshuman
            }

        case .denied_forbidden:
            decision = .denied
        }

        switch decision {
        case .approved:
            let execution = try await invoker.executeApproved(
                call,
                preflight: review.preflight,
                context: context
            )
            guard !execution.result.isError else {
                throw AgentProgramToolFailure(
                    tool: identifier,
                    result: execution.result,
                    recovery: execution.recovery
                )
            }

            return execution

        case .needshuman:
            throw AgentProgramSuspensionSignal(
                suspension: .approval(
                    PendingApproval(
                        toolCall: call,
                        preflight: review.preflight,
                        requirement: review.requirement
                    ),
                    metadata: [
                        "source": "agent_program",
                    ]
                )
            )

        case .denied:
            throw AgentProgramToolGovernanceError
                .denied(
                    identifier
                )

        case .skipped:
            throw AgentProgramToolGovernanceError
                .skipped(
                    identifier
                )
        }
    }

    public func resume(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    ) async throws -> AgentToolExecutionResult {
        let identifier = AgentToolIdentifier(
            pendingApproval.toolCall.name
        )

        switch decision {
        case .denied:
            throw AgentProgramToolGovernanceError.denied(
                identifier
            )

        case .skipped:
            throw AgentProgramToolGovernanceError.skipped(
                identifier
            )

        case .needshuman:
            throw AgentProgramSuspensionSignal(
                suspension: .approval(
                    pendingApproval,
                    metadata: [
                        "source": "agent_program",
                    ]
                )
            )

        case .approved:
            let freshReview = try await invoker.review(
                pendingApproval.toolCall,
                context: context
            )

            guard freshReview.preflight == pendingApproval.preflight,
                  freshReview.requirement == pendingApproval.requirement
            else {
                throw AgentProgramToolGovernanceError.stale_approval(
                    identifier
                )
            }

            let execution = try await invoker.executeApproved(
                pendingApproval.toolCall,
                preflight: freshReview.preflight,
                context: context
            )
            guard !execution.result.isError else {
                throw AgentProgramToolFailure(
                    tool: identifier,
                    result: execution.result,
                    recovery: execution.recovery
                )
            }

            return execution
        }
    }
}
