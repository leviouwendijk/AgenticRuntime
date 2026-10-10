public extension AgentRunner {
    func requestInterruption(
        _ mode: Run.Interruption.Mode,
        reason: String? = nil
    ) async {
        await runControl.request(
            mode,
            reason: reason
        )
    }

    func interrupt(
        sessionID: String,
        mode: Run.Interruption.Mode,
        reason: String? = nil
    ) async throws -> AgentRunner.Result {
        guard let historyStore = recording.historyStore else {
            throw AgentHistoryError.historyStoreRequired
        }

        guard let checkpoint = try await historyStore.loadCheckpoint(
            sessionID: sessionID
        ) else {
            throw AgentHistoryError.checkpointNotFound(
                sessionID
            )
        }

        let executor = try await makeAgentLoop(
            restoring: checkpoint
        )

        return try await executor.interrupt(
            checkpoint,
            mode: mode,
            reason: reason
        )
    }
}
