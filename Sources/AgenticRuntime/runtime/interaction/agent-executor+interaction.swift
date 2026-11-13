public extension AgentExecutor {
    func resume(
        interaction response: Run.Interaction.Response
    ) async throws -> AgentExecutor.Result {
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
