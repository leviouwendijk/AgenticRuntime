public protocol AgentHistoryStore: Sendable {
    func loadCheckpoint(
        sessionID: String
    ) async throws -> AgentRunner.Checkpoint?

    func saveCheckpoint(
        _ checkpoint: AgentRunner.Checkpoint
    ) async throws

    func deleteCheckpoint(
        sessionID: String
    ) async throws
}
