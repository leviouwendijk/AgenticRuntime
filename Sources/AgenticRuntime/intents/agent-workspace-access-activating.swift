import AgenticExecution
import AgenticIO

public protocol AgentWorkspaceAccessActivating: Sendable {
    func activate(
        _ plan: PreparedPathGrantOperation.Plan,
        context: PreparedOperation.Context
    ) async throws -> AgentWorkspaceAccessLease
}
