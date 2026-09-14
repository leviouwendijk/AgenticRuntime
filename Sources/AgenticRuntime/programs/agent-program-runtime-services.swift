import Agentic
import AgenticExecution
import AgenticPrograms
import AgenticRecovery
import Primitives


/// Runtime observations produced while executing one Program tool operation.
///
/// The semantic JSON output continues toward the authored typed Program API.
/// Recovery evidence remains beside it for Runtime recording and replay.
public struct AgentProgramToolExecution: Sendable {
    public var output: JSONValue
    public var recovery: Recovery.Record?

    public init(
        output: JSONValue,
        recovery: Recovery.Record? = nil
    ) {
        self.output = output
        self.recovery = recovery
    }
}

/// Runtime-side raw tool boundary used by AgentProgramRunner.
///
/// A governed AgenticExecution adapter satisfies this without exposing JSON
/// lowering or recovery bookkeeping to authored AgentProgram implementations.
public protocol AgentProgramToolExecuting: Sendable {
    func invoke(
        _ identifier: AgentToolIdentifier,
        input: JSONValue
    ) async throws -> AgentProgramToolExecution

    func resume(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    ) async throws -> AgentProgramToolExecution
}

public extension AgentProgramToolExecuting {
    func resume(
        pendingApproval: PendingApproval,
        decision _: ApprovalDecision
    ) async throws -> AgentProgramToolExecution {
        throw AgentProgramReplayError.tool_resume_unsupported(
            AgentToolIdentifier(
                pendingApproval.toolCall.name
            )
        )
    }
}

