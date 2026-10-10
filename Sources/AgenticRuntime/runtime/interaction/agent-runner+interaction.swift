public extension AgentRunner {
    func resume(
        interaction response: Run.Interaction.Response
    ) async throws -> AgentRunner.Result {
        guard let historyStore = recording.historyStore else {
            throw AgentHistoryError.historyStoreRequired
        }

        guard let checkpoint = try await historyStore.loadCheckpoint(
            sessionID: response.sessionID
        ) else {
            throw AgentHistoryError.checkpointNotFound(
                response.sessionID
            )
        }

        let executor = try await makeAgentLoop(
            restoring: checkpoint
        )

        return try await executor.resume(
            checkpoint,
            interaction: response
        )
    }
}
