public protocol AgentHistoryStore: Sendable {
    func loadCheckpoint(
        sessionID: String
    ) async throws -> AgentExecutor.Checkpoint?

    func saveCheckpoint(
        _ checkpoint: AgentExecutor.Checkpoint
    ) async throws

    func deleteCheckpoint(
        sessionID: String
    ) async throws
}
