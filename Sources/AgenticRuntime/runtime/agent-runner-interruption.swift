public extension AgentRunner {
    func requestInterruption(
        _ mode: AgentRunInterruptionMode,
        reason: String? = nil
    ) async {
        await interruptionController.request(
            mode,
            reason: reason
        )
    }

    func interrupt(
        sessionID: String,
        mode: AgentRunInterruptionMode,
        reason: String? = nil
    ) async throws -> AgentRunResult {
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

        let executor = try await makeToolLoopExecutor(
            restoring: checkpoint
        )

        return try await executor.interrupt(
            checkpoint,
            mode: mode,
            reason: reason
        )
    }
}
