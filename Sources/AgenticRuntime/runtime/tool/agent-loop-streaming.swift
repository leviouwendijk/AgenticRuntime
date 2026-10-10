import Agentic
import Foundation

extension AgentLoop {
    func performStreamingModelTurn(
        from checkpoint: AgentRunner.Checkpoint
    ) async throws -> AgentRunner.Checkpoint {
        var checkpoint = checkpoint

        try await compactIfNeeded(
            &checkpoint
        )

        // Snapshot the request's capabilities once. Request preparation,
        // advertised transport, and invocation authorization share that view.
        let projection = try await inventory.modelProjection()
        let advertisedTools = try await modelCapabilityDefinitions(
            for: projection
        )
        let preparedRequest = try await prepareModelRequest(
            from: try await requestWithCurrentState(
                from: checkpoint.originalRequest,
                messages: checkpoint.state.messages,
                definitions: advertisedTools
            ),
            checkpoint: checkpoint
        )

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

        checkpoint.lastAdvertisedCapabilities = projection
        checkpoint.lastAdvertisedTools = projection.entries.compactMap { entry in
            if case .tool(let identifier) = entry.target {
                return identifier
            }
            return nil
        }
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
            let invocation = AgentModelInvocation(
                request: preparedRequest,
                selection: model.selection,
                context: try await modelInvocationContext(
                    request: preparedRequest,
                    projection: projection,
                    advertisedTools: advertisedTools,
                    sessionID: checkpoint.id,
                    journal: journal
                )
            )

            for try await invocationEvent in model.invoker.stream(
                invocation
            ) {
                try Task.checkCancellation()

                let event: AgentStreamEvent

                switch invocationEvent {
                case .routed:
                    continue

                case .model(let modelEvent):
                    event = modelEvent

                case .completed(let result):
                    event = .completed(
                        result.response
                    )
                }

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

                checkpoint.touch()
                await publishRunState(
                    checkpoint
                )

                if let interruption = await requestedUrgentInterruption() {
                    try await interruptStreamingTurn(
                        checkpoint: &checkpoint,
                        accumulator: accumulator,
                        request: interruption
                    )
                    return checkpoint
                }

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
                nativeInvocations: await journal.snapshot(),
                nativeSemanticInvocations: await journal.semanticSnapshot()
            )
        } catch RuntimeToolCallBoundary.capabilities_changed {
            try await finishNativeCapabilityBoundary(
                invocations: await journal.snapshot(),
                semanticInvocations: await journal.semanticSnapshot(),
                checkpoint: &checkpoint
            )

            return checkpoint
        } catch AgentToolCallResolutionError.needsHumanReview(let review) {
            try await suspendForNativeApproval(
                review,
                invocations: await journal.snapshot(),
                semanticInvocations: await journal.semanticSnapshot(),
                checkpoint: &checkpoint
            )

            return checkpoint
        } catch is CancellationError {
            let interruption =
                await requestedInterruption()
                ?? Run.Interruption(
                    mode: .urgent,
                    reason: "Execution task was cancelled."
                )

            try await interruptStreamingTurn(
                checkpoint: &checkpoint,
                accumulator: accumulator,
                request: interruption
            )

            return checkpoint
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
        checkpoint: AgentRunner.Checkpoint,
        turnIndex: Int,
        nativeInvocations: [ToolInvocation.Result],
        nativeSemanticInvocations: [ModelSemanticInvocationResult]
    ) async throws -> AgentRunner.Checkpoint {
        var checkpoint = checkpoint

        checkpoint.state.iteration += 1

        try await applyNativeToolInvocations(
            nativeInvocations,
            to: &checkpoint
        )
        try await applyNativeSemanticInvocations(
            nativeSemanticInvocations,
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

    private func failStreamingTurn(
        checkpoint: inout AgentRunner.Checkpoint,
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
        checkpoint: inout AgentRunner.Checkpoint,
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
                    toolName: toolCall.tool.rawValue,
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
                    toolCallID: result.call.id,
                    toolName: result.call.tool.rawValue,
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
    ) -> Run.Event.State {
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
