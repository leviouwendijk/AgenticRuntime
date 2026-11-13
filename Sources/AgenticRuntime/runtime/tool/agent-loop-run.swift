import Agentic
import Foundation

extension AgentLoop {
    func performModelTurn(
        from checkpoint: AgentExecutor.Checkpoint
    ) async throws -> AgentExecutor.Checkpoint {
        var current = checkpoint
        try ensure_run_invocation(in: &current)
        let model_id = "model:\(UUID().uuidString)"
        try begin_invocation(
            .init(
                id: model_id,
                parent_id: AgentExecutionInvocation.root_id(session_id: current.id),
                kind: .model,
                iteration: current.state.iteration + 1
            ), to: &current
        )
        current.currentModelInvocationID = model_id
        try await saveCheckpoint(&current)

        let next: AgentExecutor.Checkpoint
        switch configuration.responseDelivery {
        case .buffered:
            next = try await performBufferedModelTurn(from: current)
        case .stream:
            next = try await performStreamingModelTurn(from: current)
        }
        current = next
        let state: AgentExecutionInvocation.State
        switch current.phase {
        case .suspended, .awaiting_approval:
            state = .suspended
        case .interrupted:
            state = .interrupted
        case .failed:
            state = .failed
        case .ready_for_model, .processing_tool_calls, .completed:
            state = .completed
        case .receiving_model_response:
            state = .running
        }
        try finish_invocation(id: model_id, state: state, to: &current)
        try await saveCheckpoint(&current)
        return current
    }

    func performBufferedModelTurn(
        from checkpoint: AgentExecutor.Checkpoint
    ) async throws -> AgentExecutor.Checkpoint {
        var checkpoint = checkpoint

        let turn = try await prepareTurn(
            &checkpoint
        )
        let projection = turn.projection
        let advertisedTools = turn.tools
        let preparedRequest = turn.request

        let turnIndex = checkpoint.state.iteration + 1

        // Buffered invocations must expose the same cancellable in-flight
        // checkpoint phase as streaming invocations, before awaiting transport.
        checkpoint.phase = .receiving_model_response
        try await saveCheckpoint(&checkpoint)

        if let interruption = await requestedUrgentInterruption() {
            try await applyInterruption(
                to: &checkpoint,
                request: interruption
            )
            return checkpoint
        }

        let invocationResult: AgentModelInvocation.Result
        let journal = AgentModelToolInvocationJournal()

        do {
            let result = try await model.invoker.buffered(
                AgentModelInvocation(
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
            )
            invocationResult = result
        } catch FunctionCallBoundaryError.capabilities_changed {
            try await finishNativeCapabilityBoundary(
                invocations: await journal.snapshot(),
                semanticInvocations: await journal.semanticSnapshot(),
                checkpoint: &checkpoint
            )

            return checkpoint
        } catch FunctionCallResolutionError.needsHumanReview(let review) {
            try await suspendForNativeApproval(
                review,
                invocations: await journal.snapshot(),
                semanticInvocations: await journal.semanticSnapshot(),
                checkpoint: &checkpoint
            )

            return checkpoint
        } catch let pending as RuntimeDelegatedChildSuspension {
            try await suspendNativeDelegatedChild(
                pending,
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

            try await applyInterruption(
                to: &checkpoint,
                request: interruption
            )

            return checkpoint
        } catch {
            let failure = AgentRunFailure.modelInvocationFailed(
                error
            )
            checkpoint.phase = .failed
            checkpoint.failure = failure

            try await appendRunEvent(
                .init(
                    kind: .run_failed,
                    iteration: checkpoint.state.iteration,
                    summary: failure.message
                ),
                to: &checkpoint
            )

            try await saveCheckpoint(
                &checkpoint
            )

            return checkpoint
        }

        let response = invocationResult.response
        checkpoint.state.iteration += 1

        try await applyNativeToolInvocations(
            await journal.snapshot(),
            to: &checkpoint
        )
        try await applyNativeSemanticInvocations(
            await journal.semanticSnapshot(),
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

        try await applyProjectedCost(
            for: preparedRequest,
            route: invocationResult.route.route,
            to: &checkpoint,
            turnIndex: turnIndex
        )
        try await applyActualCost(
            response: response,
            route: invocationResult.route,
            to: &checkpoint,
            turnIndex: turnIndex
        )

        for harnessExtension in extensions {
            try await harnessExtension.didReceive(
                response: response,
                state: checkpoint.state
            )
        }

        let functionCalls = functionCalls(
            in: response.message
        )

        checkpoint.phase = flow.phase(
            after: response,
            calls: functionCalls
        )

        if let interruption = await requestedUrgentInterruption() {
            try await applyInterruption(
                to: &checkpoint,
                request: interruption
            )
            return checkpoint
        }

        try await saveCheckpoint(
            &checkpoint
        )

        return checkpoint
    }
}
