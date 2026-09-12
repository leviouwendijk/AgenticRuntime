import Agentic
import AgenticExecution
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
    case missing_tool_result(AgentToolIdentifier)
    case tool_execution_failed(AgentToolIdentifier)
    case stale_approval(AgentToolIdentifier)

    public var errorDescription: String? {
        switch self {
        case .needs_human_review(let identifier):
            return "Program tool '\(identifier.rawValue)' requires human review before execution."

        case .denied(let identifier):
            return "Program tool '\(identifier.rawValue)' was denied by execution policy or approval."

        case .skipped(let identifier):
            return "Program tool '\(identifier.rawValue)' was skipped by approval handling."

        case .missing_tool_result(let identifier):
            return "Approved Program tool '\(identifier.rawValue)' completed without a tool result."

        case .tool_execution_failed(let identifier):
            return "Program tool '\(identifier.rawValue)' returned a failed tool result."

        case .stale_approval(let identifier):
            return "Program tool '\(identifier.rawValue)' changed since approval was requested; the stale approval was not executed."
        }
    }
}

/// Bridges an authored AgentProgram tool request into AgenticExecution's
/// canonical governed invocation path.
///
/// The Program identifies the semantic operation it needs. It does not receive
/// authority to execute that operation directly. ToolInvoker remains responsible
/// for registry resolution, preflight, execution policy, approval, and execution.
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
        context: AgentToolExecutionContext = .init(),
        approvalHandler: (any ToolApprovalHandler)? = nil
    ) {
        self.init(
            invoker: ToolInvoker(
                registry: registry,
                policy: policy
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
    ) async throws -> JSONValue {
        let call = AgentToolCall(
            id: "program-\(UUID().uuidString)",
            name: identifier.rawValue,
            input: input
        )
        let result = try await invoker.invoke(
            call,
            context: context,
            approvalHandler: approvalHandler
        )

        switch result.decision {
        case .approved:
            guard let toolResult = result.toolResult else {
                throw AgentProgramToolGovernanceError
                    .missing_tool_result(
                        identifier
                    )
            }

            guard !toolResult.isError else {
                throw AgentProgramToolGovernanceError
                    .tool_execution_failed(
                        identifier
                    )
            }

            return toolResult.output

        case .needshuman:
            throw AgentProgramToolGovernanceError
                .needs_human_review(
                    identifier
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
    ) async throws -> JSONValue {
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
            throw AgentProgramToolGovernanceError.needs_human_review(
                identifier
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

            let toolResult = try await invoker.registry.execute(
                pendingApproval.toolCall,
                context: context
            )

            guard !toolResult.isError else {
                throw AgentProgramToolGovernanceError
                    .tool_execution_failed(
                        identifier
                    )
            }

            return toolResult.output
        }
    }
}
