import Agentic
import AgenticExecution
import Foundation

extension ToolLoopExecutor {
    func performStreamingModelTurn(
        from checkpoint: AgentHistoryCheckpoint
    ) async throws -> AgentHistoryCheckpoint {
        var checkpoint = checkpoint

        try await compactIfNeeded(
            &checkpoint
        )

        var preparedRequest = try await requestWithCurrentState(
            from: checkpoint.originalRequest,
            messages: checkpoint.state.messages
        )

        for harnessExtension in extensions {
            preparedRequest = try await harnessExtension.prepare(
                request: preparedRequest,
                state: checkpoint.state
            )
        }

        let turnIndex = checkpoint.state.iteration + 1

        try await applyProjectedCost(
            for: preparedRequest,
            to: &checkpoint,
            turnIndex: turnIndex
        )

        var accumulator = AgentStreamAccumulator(
            messageID: UUID().uuidString
        )
        var checkpointState = AgentStreamCheckpointState()
        let journal = AgentModelToolInvocationJournal()

        checkpoint.phase = .receiving_model_response
        checkpoint.partialResponse = accumulator.partial

        try await appendRunEvent(
            .init(
                kind: .model_stream_started,
                iteration: checkpoint.state.iteration,
                messageID: accumulator.partial.messageID,
                summary: "model stream started"
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        do {
            for try await event in adapter.respond(
                request: preparedRequest,
                delivery: .stream,
                context: modelInvocationContext(
                    sessionID: checkpoint.id,
                    journal: journal
                )
            ) {
                try Task.checkCancellation()

                try accumulator.consume(
                    event
                )

                checkpoint.partialResponse = accumulator.partial

                try await recordStreamProgress(
                    event,
                    accumulator: accumulator,
                    checkpoint: &checkpoint,
                    checkpointState: &checkpointState
                )

                if checkpointState.shouldSave(
                    event: event,
                    policy: configuration.streamCheckpointPolicy
                ) {
                    try await appendRunEvent(
                        checkpointState.checkpointEvent(
                            accumulator: accumulator,
                            iteration: checkpoint.state.iteration
                        ),
                        to: &checkpoint
                    )

                    try await saveCheckpoint(
                        &checkpoint
                    )

                    checkpointState.markSaved(
                        accumulator: accumulator
                    )
                }
            }

            try Task.checkCancellation()

            guard let response = accumulator.completedResponse else {
                throw AgentStreamingError.missingCompletedResponse
            }

            return try await finalizeStreamingModelTurn(
                preparedRequest: preparedRequest,
                response: response,
                checkpoint: checkpoint,
                turnIndex: turnIndex,
                nativeInvocations: await journal.snapshot()
            )
        } catch RuntimeAgentToolCallBoundary.exposure_changed {
            try await finishNativeExposureBoundary(
                invocations: await journal.snapshot(),
                checkpoint: &checkpoint
            )

            return checkpoint
        } catch AgentToolCallResolutionError.needsHumanReview(let review) {
            try await suspendForNativeApproval(
                review,
                invocations: await journal.snapshot(),
                checkpoint: &checkpoint
            )

            return checkpoint
        } catch is CancellationError {
            try await interruptStreamingTurn(
                checkpoint: &checkpoint,
                accumulator: accumulator
            )

            throw CancellationError()
        } catch {
            try await failStreamingTurn(
                checkpoint: &checkpoint,
                accumulator: accumulator,
                error: error
            )

            return checkpoint
        }
    }

    private func finalizeStreamingModelTurn(
        preparedRequest: AgentRequest,
        response: AgentResponse,
        checkpoint: AgentHistoryCheckpoint,
        turnIndex: Int,
        nativeInvocations: [ToolInvocation.Result]
    ) async throws -> AgentHistoryCheckpoint {
        var checkpoint = checkpoint

        checkpoint.state.iteration += 1

        try await applyNativeToolInvocations(
            nativeInvocations,
            to: &checkpoint
        )

        checkpoint.state.messages.append(
            response.message
        )
        checkpoint.lastResponse = response
        checkpoint.partialResponse = nil
        checkpoint.clearSuspension()

        try await recordMessage(
            response.message
        )

        try await appendRunEvent(
            .init(
                kind: .assistant_response,
                iteration: checkpoint.state.iteration,
                messageID: response.message.id,
                summary: response.stopReason.rawValue
            ),
            to: &checkpoint
        )

        try await applyActualCost(
            for: preparedRequest,
            response: response,
            to: &checkpoint,
            turnIndex: turnIndex
        )

        for harnessExtension in extensions {
            try await harnessExtension.didReceive(
                response: response,
                state: checkpoint.state
            )
        }

        let toolCalls = toolCalls(
            in: response.message
        )

        if response.stopReason == AgentStopReason.tool_use,
           !toolCalls.isEmpty {
            checkpoint.phase = .processing_tool_calls
        } else {
            checkpoint.phase = .completed
        }

        try await saveCheckpoint(
            &checkpoint
        )

        return checkpoint
    }

    private func interruptStreamingTurn(
        checkpoint: inout AgentHistoryCheckpoint,
        accumulator: AgentStreamAccumulator
    ) async throws {
        checkpoint.phase = .interrupted
        checkpoint.partialResponse = accumulator.partial

        try await appendRunEvent(
            .init(
                kind: .model_stream_interrupted,
                iteration: checkpoint.state.iteration,
                messageID: accumulator.partial.messageID,
                summary: "model stream interrupted"
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )
    }

    private func failStreamingTurn(
        checkpoint: inout AgentHistoryCheckpoint,
        accumulator: AgentStreamAccumulator,
        error: Error
    ) async throws {
        let failure = AgentRunFailure.modelInvocationFailed(
            error
        )
        checkpoint.phase = .failed
        checkpoint.failure = failure
        checkpoint.partialResponse = accumulator.partial

        try await appendRunEvent(
            .init(
                kind: .model_stream_failed,
                iteration: checkpoint.state.iteration,
                messageID: accumulator.partial.messageID,
                summary: failure.message
            ),
            to: &checkpoint
        )

        try await appendRunEvent(
            .init(
                kind: .run_failed,
                iteration: checkpoint.state.iteration,
                messageID: accumulator.partial.messageID,
                summary: failure.message
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )
    }

    private func recordStreamProgress(
        _ event: AgentStreamEvent,
        accumulator: AgentStreamAccumulator,
        checkpoint: inout AgentHistoryCheckpoint,
        checkpointState: inout AgentStreamCheckpointState
    ) async throws {
        checkpointState.record(
            event
        )

        switch event {
        case .messagedelta:
            return

        case .toolcall(let toolCall):
            try await appendRunEvent(
                .init(
                    kind: .model_stream_tool_call,
                    iteration: checkpoint.state.iteration,
                    messageID: accumulator.partial.messageID,
                    toolCallID: toolCall.id,
                    toolName: toolCall.name,
                    summary: "streamed tool call"
                ),
                to: &checkpoint
            )

        case .toolresult(let result):
            try await appendRunEvent(
                .init(
                    kind: result.isError ? .tool_error : .tool_result,
                    iteration: checkpoint.state.iteration,
                    messageID: accumulator.partial.messageID,
                    toolCallID: result.toolCallID,
                    toolName: result.name,
                    summary: result.isError
                        ? "streamed tool result error"
                        : "streamed tool result"
                ),
                to: &checkpoint
            )

        case .completed(let response):
            try await appendRunEvent(
                .init(
                    kind: .model_stream_completed,
                    iteration: checkpoint.state.iteration,
                    messageID: response.message.id,
                    summary: response.stopReason.rawValue
                ),
                to: &checkpoint
            )
        }
    }
}

private struct AgentStreamCheckpointState {
    private var eventCount: Int = 0
    private var lastSavedEventCount: Int = 0
    private var characterCount: Int = 0
    private var lastSavedCharacterCount: Int = 0
    private var lastSavedAt: Date = Date()

    mutating func record(
        _ event: AgentStreamEvent
    ) {
        eventCount += 1
        characterCount += characterCount(
            for: event
        )
    }

    func shouldSave(
        event: AgentStreamEvent,
        policy: AgentStreamCheckpointPolicy
    ) -> Bool {
        guard case .messagedelta = event else {
            return false
        }

        let eventDelta = eventCount - lastSavedEventCount
        let characterDelta = characterCount - lastSavedCharacterCount
        let elapsed = Date().timeIntervalSince(
            lastSavedAt
        )

        return eventDelta >= policy.eventInterval
            || characterDelta >= policy.characterInterval
            || elapsed >= policy.minimumSecondsBetweenCheckpoints
    }

    func checkpointEvent(
        accumulator: AgentStreamAccumulator,
        iteration: Int
    ) -> AgentRunEvent {
        .init(
            kind: .assistant_delta,
            iteration: iteration,
            messageID: accumulator.partial.messageID,
            summary: "stream checkpoint events=\(eventCount) characters=\(characterCount)"
        )
    }

    mutating func markSaved(
        accumulator: AgentStreamAccumulator
    ) {
        lastSavedEventCount = eventCount
        lastSavedCharacterCount = characterCount
        lastSavedAt = Date()
    }

    private func characterCount(
        for event: AgentStreamEvent
    ) -> Int {
        guard case .messagedelta(let block) = event,
              case .text(let value) = block
        else {
            return 0
        }

        return value.count
    }
}
