import AgenticExecution

public extension AgentRunner {
    func resume(
        sessionID: String,
        approvalDecision: ApprovalDecision,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        guard let historyStore else {
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

        return try await executor.resume(
            checkpoint,
            approvalDecision: approvalDecision,
            metadata: metadata
        )
    }
}
