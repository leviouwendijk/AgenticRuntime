public protocol AgentHistoryStore: Sendable {
    func loadCheckpoint(
        sessionID: String
    ) async throws -> AgentHistoryCheckpoint?

    func saveCheckpoint(
        _ checkpoint: AgentHistoryCheckpoint
    ) async throws

    func deleteCheckpoint(
        sessionID: String
    ) async throws
}
