import Agentic

public extension AgentExecutor {
    func resume(
        sessionID: String,
        approvalDecision: ApprovalDecision,
        metadata: [String: String] = [:]
    ) async throws -> AgentExecutor.Result {
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

        return try await executor.resume(
            checkpoint,
            approvalDecision: approvalDecision,
            metadata: metadata
        )
    }
}
