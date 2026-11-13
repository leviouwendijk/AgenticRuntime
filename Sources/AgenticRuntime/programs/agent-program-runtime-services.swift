import Agentic
import Primitives


/// Runtime-side governed tool boundary used by ProgramExecutor.
///
/// Implementations may own approval, suspension, and resume semantics, while
/// successful tool execution returns AgenticExecution's canonical mechanical result.
public protocol GovernedToolExecuting: Sendable {
    func execute(
        _ identifier: ToolIdentifier,
        input: JSONValue
    ) async throws -> ToolExecution.Result

    func resume(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    ) async throws -> ToolExecution.Result
}

public extension GovernedToolExecuting {
    func resume(
        pendingApproval: PendingApproval,
        decision _: ApprovalDecision
    ) async throws -> ToolExecution.Result {
        throw ProgramReplayError.tool_resume_unsupported(
            ToolIdentifier(pendingApproval.functionCall.name)
        )
    }
}
