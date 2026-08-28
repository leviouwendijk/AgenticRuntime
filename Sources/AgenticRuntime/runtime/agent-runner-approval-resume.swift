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

        return try await ToolLoopExecutor(
            adapter: adapter,
            configuration: configuration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            workspace: workspace,
            approvalHandler: approvalHandler,
            historyStore: historyStore,
            eventSinks: eventSinks,
            costTracker: costTracker
        ).resume(
            checkpoint,
            approvalDecision: approvalDecision,
            metadata: metadata
        )
    }
}
