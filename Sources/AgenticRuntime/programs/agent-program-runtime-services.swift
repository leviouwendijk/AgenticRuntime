import Agentic
import Primitives


/// Runtime-side governed tool boundary used by ProgramRunner.
///
/// Implementations may own approval, suspension, and resume semantics, while
/// successful tool execution returns AgenticExecution's canonical mechanical result.
public protocol ProgramToolExecuting: Sendable {
    func invoke(
        _ identifier: ToolIdentifier,
        input: JSONValue
    ) async throws -> ToolExecutionResult

    func resume(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    ) async throws -> ToolExecutionResult
}

public extension ProgramToolExecuting {
    func resume(
        pendingApproval: PendingApproval,
        decision _: ApprovalDecision
    ) async throws -> ToolExecutionResult {
        throw ProgramReplayError.tool_resume_unsupported(
            pendingApproval.toolCall.tool
        )
    }
}
