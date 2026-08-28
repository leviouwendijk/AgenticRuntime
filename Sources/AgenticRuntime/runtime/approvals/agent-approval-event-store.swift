public protocol AgentApprovalEventStore: Sendable {
    func loadEvents() async throws -> [AgentApprovalEvent]

    func append(
        _ event: AgentApprovalEvent
    ) async throws
}
