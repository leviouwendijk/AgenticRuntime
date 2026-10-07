public extension AgentRunner {
    func resume(
        interaction response: Run.Interaction.Response
    ) async throws -> AgentRunResult {
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

        let executor = try await makeToolLoopExecutor(
            restoring: checkpoint
        )

        return try await executor.resume(
            checkpoint,
            interaction: response
        )
    }
}
