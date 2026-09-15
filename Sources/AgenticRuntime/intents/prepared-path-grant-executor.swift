import AgenticExecution
import AgenticIO

public struct PreparedPathGrantExecutor:
    AgentPreparedOperation,
    Sendable
{
    public typealias Plan = PreparedPathGrantOperation.Plan

    public static let schema = PreparedPathGrantOperation.schema

    public struct Result:
        Sendable,
        Codable,
        Hashable
    {
        public let lease: AgentWorkspaceAccessLease

        public init(
            lease: AgentWorkspaceAccessLease
        ) {
            self.lease = lease
        }
    }

    public let activator: any AgentWorkspaceAccessActivating

    public init(
        activator: any AgentWorkspaceAccessActivating
    ) {
        self.activator = activator
    }

    public func execute(
        _ plan: Plan,
        context: PreparedOperation.Context
    ) async throws -> Result {
        .init(
            lease: try await activator.activate(
                plan,
                context: context
            )
        )
    }
}
