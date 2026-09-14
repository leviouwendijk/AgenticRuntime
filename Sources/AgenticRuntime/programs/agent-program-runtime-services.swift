import Agentic
import AgenticExecution
import AgenticPrograms
import Primitives


/// Runtime-side governed tool boundary used by AgentProgramRunner.
///
/// Implementations may own approval, suspension, and resume semantics, while
/// successful tool execution returns Runtime's canonical mechanical result.
public protocol AgentProgramToolExecuting: Sendable {
    func invoke(
        _ identifier: AgentToolIdentifier,
        input: JSONValue
    ) async throws -> AgentToolExecutionResult

    func resume(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    ) async throws -> AgentToolExecutionResult
}

public extension AgentProgramToolExecuting {
    func resume(
        pendingApproval: PendingApproval,
        decision _: ApprovalDecision
    ) async throws -> AgentToolExecutionResult {
        throw AgentProgramReplayError.tool_resume_unsupported(
            AgentToolIdentifier(
                pendingApproval.toolCall.name
            )
        )
    }
}

