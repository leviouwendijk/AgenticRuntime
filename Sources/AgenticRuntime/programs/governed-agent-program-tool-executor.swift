import Agentic
import Foundation
import Primitives

public enum ProgramToolGovernanceError:
    Error,
    Sendable,
    LocalizedError
{
    case needs_human_review(ToolIdentifier)
    case denied(ToolIdentifier)
    case skipped(ToolIdentifier)
    case stale_approval(ToolIdentifier)

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

/// Bridges an authored Program tool request into AgenticExecution's
/// canonical governed invocation path.
///
/// The Program identifies the semantic operation it needs. It does not receive
/// authority to execute that operation directly. Runtime owns Program approval,
/// suspension, and resume semantics while ToolInvoker owns review and canonical
/// mechanical execution.
public struct GovernedProgramToolExecutor:
    ProgramToolExecuting,
    Sendable
{
    public let invoker: ToolInvoker
    public let context: ToolContext
    public let approvalHandler: (any ToolApprovalHandler)?

    public init(
        registry: ToolRegistry,
        policy: ToolExecutionPolicy,
        recovery: Recovery.Policy? = nil,
        context: ToolContext = .init(),
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
        context: ToolContext = .init(),
        approvalHandler: (any ToolApprovalHandler)? = nil
    ) {
        self.invoker = invoker
        self.context = context
        self.approvalHandler = approvalHandler
    }

    public func invoke(
        _ identifier: ToolIdentifier,
        input: JSONValue
    ) async throws -> ToolExecutionResult {
        let invocation = ToolInvocation(
            id: "program-\(UUID().uuidString)",
            tool: identifier,
            arguments: input
        )
        let invocationResult = try await invoker.invoke(
            invocation,
            context: context,
            approvalHandler: approvalHandler
        )

        return try resolve(
            invocationResult,
            identifier: identifier,
            source: "agent_program"
        )
    }

    public func resume(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    ) async throws -> ToolExecutionResult {
        let identifier = pendingApproval.toolCall.tool

        switch decision {
        case .denied:
            throw ProgramToolGovernanceError.denied(
                identifier
            )

        case .skipped:
            throw ProgramToolGovernanceError.skipped(
                identifier
            )

        case .needshuman:
            throw ProgramSuspensionSignal(
                suspension: .approval(
                    pendingApproval,
                    metadata: [
                        "source": "agent_program",
                    ]
                )
            )

        case .approved:
            let invocation = ToolInvocation(
                id: pendingApproval.toolCall.id,
                tool: pendingApproval.toolCall.tool,
                arguments: pendingApproval.toolCall.input
            )
            let freshReview = try await invoker.review(
                invocation,
                context: context
            )

            guard freshReview.preflight == pendingApproval.preflight,
                  freshReview.requirement == pendingApproval.requirement
            else {
                throw ProgramToolGovernanceError.stale_approval(
                    identifier
                )
            }

            let invocationResult = try await invoker.invoke(
                freshReview,
                context: context,
                approvalHandler: ProgramResolvedApprovalHandler(
                    decision: .approved
                )
            )

            return try resolve(
                invocationResult,
                identifier: identifier,
                source: "agent_program"
            )
        }
    }

    private func resolve(
        _ invocation: ToolInvocation.Result,
        identifier: ToolIdentifier,
        source: String
    ) throws -> ToolExecutionResult {
        switch invocation.outcome {
        case .executed(let execution):
            guard !execution.result.isError else {
                throw ProgramToolFailure(
                    tool: identifier,
                    result: execution.result,
                    recovery: execution.recovery
                )
            }

            return execution

        case .interrupted(.human_review):
            throw ProgramSuspensionSignal(
                suspension: .approval(
                    PendingApproval(
                        toolCall: ToolCall(
                            id: invocation.review.invocation.id,
                            tool: invocation.review.invocation.tool,
                            input: invocation.review.invocation.arguments
                        ),
                        preflight: invocation.review.preflight,
                        requirement: invocation.review.requirement
                    ),
                    metadata: [
                        "source": source,
                    ]
                )
            )

        case .denied:
            throw ProgramToolGovernanceError.denied(
                identifier
            )

        case .skipped:
            throw ProgramToolGovernanceError.skipped(
                identifier
            )
        }
    }
}

private struct ProgramResolvedApprovalHandler:
    ToolApprovalHandler,
    Sendable
{
    let decision: ApprovalDecision

    func decide(
        on _: ToolPreflight,
        requirement _: ApprovalRequirement
    ) async throws -> ApprovalDecision {
        decision
    }
}
