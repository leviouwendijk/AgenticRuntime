import Agentic
import AgenticRecovery

/// Canonical Runtime result of one tool execution path.
///
/// `result` preserves the operation-facing tool contract. `recovery` preserves
/// mechanical recovery and reconciliation evidence accumulated by Runtime.
public struct AgentToolExecutionResult: Sendable {
    public var result: AgentToolResult
    public var recovery: Recovery.Record?

    public init(
        result: AgentToolResult,
        recovery: Recovery.Record? = nil
    ) {
        self.result = result
        self.recovery = recovery
    }
}
