public extension AgentRunner {
    func resume(
        interaction response: AgentInteraction.Response
    ) async throws -> AgentRunResult {
        guard let historyStore else {
            throw AgentHistoryError.historyStoreRequired
        }

        guard let checkpoint = try await historyStore.loadCheckpoint(
            sessionID: response.sessionID
        ) else {
            throw AgentHistoryError.checkpointNotFound(
                response.sessionID
            )
        }

        guard checkpoint.id == response.sessionID else {
            throw AgentInteractionError.sessionMismatch(
                expected: checkpoint.id,
                received: response.sessionID
            )
        }

        guard let suspension = checkpoint.resolvedSuspension else {
            throw AgentInteractionError.noCurrentSuspension(
                sessionID: checkpoint.id
            )
        }

        guard suspension.id == response.requestID else {
            throw AgentInteractionError.requestMismatch(
                expected: suspension.id,
                received: response.requestID
            )
        }

        let expectedKind = suspension.reason.interactionKind

        guard expectedKind == response.kind else {
            throw AgentInteractionError.resolutionMismatch(
                expected: expectedKind,
                received: response.kind
            )
        }

        let executor = try await makeToolLoopExecutor(
            restoring: checkpoint
        )

        switch response.resolution {
        case .approval(let decision):
            return try await executor.resume(
                checkpoint,
                approvalDecision: decision,
                metadata: response.metadata
            )

        case .user_input(let answer):
            return try await executor.resume(
                checkpoint,
                answer: answer,
                metadata: response.metadata
            )
        }
    }
}
