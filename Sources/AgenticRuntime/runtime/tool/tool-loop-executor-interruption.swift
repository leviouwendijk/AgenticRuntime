import Agentic

extension ToolLoopExecutor {
    func interrupt(
        _ checkpoint: AgentHistoryCheckpoint,
        mode: AgentRunInterruptionMode,
        reason: String? = nil
    ) async throws -> AgentRunResult {
        var checkpoint = checkpoint

        try await applyInterruption(
            to: &checkpoint,
            request: .init(
                mode: mode,
                reason: reason
            )
        )

        return .interrupted(
            sessionID: checkpoint.id,
            response: checkpoint.lastResponse,
            state: checkpoint.state,
            events: checkpoint.events,
            toolUses: checkpoint.resolvedToolUses,
            costRecord: checkpoint.costRecord
        )
    }

    func requestedInterruption() async -> AgentRunInterruptionRequest? {
        await interruptionController.current()
    }

    func requestedUrgentInterruption() async -> AgentRunInterruptionRequest? {
        guard let request = await requestedInterruption(),
              request.mode == .urgent else {
            return nil
        }

        return request
    }

    func applyInterruption(
        to checkpoint: inout AgentHistoryCheckpoint,
        request: AgentRunInterruptionRequest
    ) async throws {
        try await closeOutstandingToolCallsForInterruption(
            in: &checkpoint
        )

        checkpoint.clearSuspension()
        checkpoint.phase = .interrupted
        checkpoint.failure = nil

        try await appendRunEvent(
            .init(
                kind: .run_interrupted,
                iteration: checkpoint.state.iteration,
                summary: interruptionSummary(
                    request
                )
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        await interruptionController.clear()
    }

    func interruptStreamingTurn(
        checkpoint: inout AgentHistoryCheckpoint,
        accumulator: AgentStreamAccumulator,
        request: AgentRunInterruptionRequest
    ) async throws {
        checkpoint.partialResponse = accumulator.partial

        let partial = accumulator.partial
        if !partial.blocks.isEmpty,
           !checkpoint.state.messages.contains(where: { message in
               message.id == partial.messageID
           })
        {
            let message = partial.message
            checkpoint.state.messages.append(
                message
            )
            try await recordMessage(
                message
            )
        }

        try await appendRunEvent(
            .init(
                kind: .model_stream_interrupted,
                iteration: checkpoint.state.iteration,
                messageID: partial.messageID,
                summary: "model stream interrupted"
            ),
            to: &checkpoint
        )

        try await applyInterruption(
            to: &checkpoint,
            request: request
        )
    }

    private func closeOutstandingToolCallsForInterruption(
        in checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        if checkpoint.toolBatch == nil,
           let response = checkpoint.lastResponse,
           !toolCalls(in: response.message).isEmpty
        {
            checkpoint.toolBatch = AgentToolUseBatch(
                response: response
            )
        }

        guard let batch = checkpoint.toolBatch else {
            return
        }

        let reason =
            "Skipped because the user interrupted this run before this tool call executed."

        for record in batch.records where !record.isTerminal {
            let result = makeSkippedToolResult(
                for: record.toolCall,
                disposition: .skipped_by_user,
                reason: reason
            )

            try await appendToolResult(
                result,
                for: record.toolCall,
                disposition: .skipped_by_user,
                to: &checkpoint,
                summary: "skipped because run was interrupted"
            )
        }

        finishToolBatch(
            on: &checkpoint
        )
    }

    private func interruptionSummary(
        _ request: AgentRunInterruptionRequest
    ) -> String {
        let prefix: String

        switch request.mode {
        case .after_iteration:
            prefix = "Run stopped at the next iteration boundary."

        case .urgent:
            prefix = "Run stopped at the earliest safe boundary."
        }

        guard let reason = request.reason,
              !reason.isEmpty else {
            return prefix
        }

        return "\(prefix) \(reason)"
    }
}
