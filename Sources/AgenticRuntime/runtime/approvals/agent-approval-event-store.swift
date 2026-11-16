import AgenticSessions
public protocol AgentApprovalEventStore: Sendable {
    func loadEvents() async throws -> [Sessions.ApprovalEvent]

    func append(
        _ event: Sessions.ApprovalEvent
    ) async throws
}
