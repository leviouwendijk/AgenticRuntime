import Agentic
import Foundation

extension ToolLoopExecutor {
    func runLoop(
        from initialCheckpoint: AgentHistoryCheckpoint
    ) async throws -> AgentRunResult {
        var checkpoint = initialCheckpoint

        while true {
            switch checkpoint.phase {
            case .ready_for_model:
                if let interruption = await requestedInterruption() {
                    return try await interrupt(
                        checkpoint,
                        mode: interruption.mode,
                        reason: interruption.reason
                    )
                }

                if let exhaustion = runLimitExhaustion(
                    in: checkpoint
                ) {
                    return try await suspendForRunLimit(
                        exhaustion,
                        checkpoint: &checkpoint
                    )
                }

                checkpoint = try await performModelTurn(
                    from: checkpoint
                )

                if checkpoint.phase == .completed {
                    guard let response = checkpoint.lastResponse else {
                        throw AgentHistoryError.corruptedCheckpoint(
                            "completed checkpoint without final response"
                        )
                    }

                    return .completed(
                        sessionID: checkpoint.id,
                        response: response,
                        state: checkpoint.state,
                        events: checkpoint.events,
                        toolUses: checkpoint.resolvedToolUses,
                        costRecord: checkpoint.costRecord
                    )
                }

            case .receiving_model_response:
                throw AgentStreamingError.receivingModelResponseCheckpoint(
                    checkpoint.id
                )

            case .processing_tool_calls:
                let processed = try await processToolCalls(
                    from: checkpoint
                )

                switch processed {
                case .continueLoop(let updatedCheckpoint):
                    checkpoint = updatedCheckpoint

                case .result(let result):
                    return result
                }

            case .suspended,
                 .awaiting_approval:
                return try suspendedResult(
                    from: checkpoint
                )

            case .interrupted:
                return .interrupted(
                    sessionID: checkpoint.id,
                    response: checkpoint.lastResponse,
                    state: checkpoint.state,
                    events: checkpoint.events,
                    toolUses: checkpoint.resolvedToolUses,
                    costRecord: checkpoint.costRecord
                )

            case .failed:
                guard let failure = checkpoint.failure else {
                    throw AgentStreamingError.failedCheckpoint(
                        checkpoint.id
                    )
                }

                return .failed(
                    sessionID: checkpoint.id,
                    failure: failure,
                    response: checkpoint.lastResponse,
                    state: checkpoint.state,
                    events: checkpoint.events,
                    toolUses: checkpoint.resolvedToolUses,
                    costRecord: checkpoint.costRecord
                )

            case .completed:
                guard let response = checkpoint.lastResponse else {
                    throw AgentHistoryError.corruptedCheckpoint(
                        "completed checkpoint without final response"
                    )
                }

                return .completed(
                    sessionID: checkpoint.id,
                    response: response,
                    state: checkpoint.state,
                    events: checkpoint.events,
                    toolUses: checkpoint.resolvedToolUses,
                    costRecord: checkpoint.costRecord
                )
            }
        }
    }

    func performModelTurn(
        from checkpoint: AgentHistoryCheckpoint
    ) async throws -> AgentHistoryCheckpoint {
        switch configuration.responseDelivery {
        case .buffered:
            return try await performBufferedModelTurn(
                from: checkpoint
            )

        case .stream:
            return try await performStreamingModelTurn(
                from: checkpoint
            )
        }
    }

    func performBufferedModelTurn(
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

        let response: AgentResponse
        let journal = AgentModelToolInvocationJournal()

        do {
            let result = try await model.invoker.buffered(
                AgentModelInvocation(
                    request: preparedRequest,
                    selection: model.selection,
                    context: await modelInvocationContext(
                        sessionID: checkpoint.id,
                        journal: journal
                    )
                )
            )
            response = result.response
        } catch RuntimeToolCallBoundary.capabilities_changed {
            try await finishNativeCapabilityBoundary(
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

        checkpoint.state.iteration += 1

        try await applyNativeToolInvocations(
            await journal.snapshot(),
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

    // func processToolCalls(
    //     from checkpoint: AgentHistoryCheckpoint
    // ) async throws -> ToolProcessingOutcome {
    //     var checkpoint = checkpoint

    //     guard let response = checkpoint.lastResponse else {
    //         throw AgentHistoryError.corruptedCheckpoint(
    //             "processing tool calls without last response"
    //         )
    //     }

    //     let calls = toolCalls(
    //         in: response.message
    //     )

    //     guard !calls.isEmpty else {
    //         checkpoint.phase = .ready_for_model
    //         checkpoint.lastResponse = nil
    //         checkpoint.clearSuspension()

    //         try await saveCheckpoint(
    //             &checkpoint
    //         )

    //         return .continueLoop(checkpoint)
    //     }

    //     for toolCall in calls {
    //         if toolCall.name == Standard.Tools.ClarifyWithUser.identifier.rawValue {
    //             return try await suspendForUserInput(
    //                 toolCall,
    //                 checkpoint: &checkpoint
    //             )
    //         }

    //         try await recordToolCall(
    //             toolCall
    //         )

    //         let preflight: ToolPreflight

    //         do {
    //             preflight = try await toolRegistry.preflight(
    //                 toolCall,
    //                 workspace: workspace
    //             )
    //         } catch {
    //             let result = makeToolErrorResult(
    //                 for: toolCall,
    //                 error: error
    //             )

    //             appendToolResultBlock(
    //                 .tool_result(result),
    //                 to: &checkpoint.state
    //             )

    //             try await recordToolResult(
    //                 result
    //             )

    //             try await appendRunEvent(
    //                 .init(
    //                     kind: .tool_error,
    //                     iteration: checkpoint.state.iteration,
    //                     toolCallID: toolCall.id,
    //                     toolName: toolCall.name,
    //                     summary: localizedDescription(for: error)
    //                 ),
    //                 to: &checkpoint
    //             )

    //             try await saveCheckpoint(
    //                 &checkpoint
    //             )

    //             continue
    //         }

    //         try await appendRunEvent(
    //             .init(
    //                 kind: .tool_preflight,
    //                 iteration: checkpoint.state.iteration,
    //                 toolCallID: toolCall.id,
    //                 toolName: toolCall.name,
    //                 summary: preflight.summary
    //             ),
    //             to: &checkpoint
    //         )

    //         let requirement = configuration.toolExecutionPolicy.evaluate(
    //             preflight
    //         )

    //         switch requirement {
    //         case .no_approval_needed:
    //             try await appendRunEvent(
    //                 .init(
    //                     kind: .tool_approved,
    //                     iteration: checkpoint.state.iteration,
    //                     toolCallID: toolCall.id,
    //                     toolName: toolCall.name,
    //                     summary: "auto-approved by execution policy"
    //                 ),
    //                 to: &checkpoint
    //             )

    //             let result = await executeApprovedToolCall(
    //                 toolCall
    //             )

    //             appendToolResultBlock(
    //                 .tool_result(result),
    //                 to: &checkpoint.state
    //             )

    //             try await recordToolResult(
    //                 result
    //             )

    //             try await appendRunEvent(
    //                 .init(
    //                     kind: result.isError ? .tool_error : .tool_result,
    //                     iteration: checkpoint.state.iteration,
    //                     toolCallID: toolCall.id,
    //                     toolName: toolCall.name,
    //                     summary: result.isError
    //                         ? "tool execution failed"
    //                         : "tool executed"
    //                 ),
    //                 to: &checkpoint
    //             )

    //             try await saveCheckpoint(
    //                 &checkpoint
    //             )

    //         case .denied_forbidden:
    //             let result = makeDeniedToolResult(
    //                 for: toolCall,
    //                 preflight: preflight,
    //                 requirement: requirement
    //             )

    //             appendToolResultBlock(
    //                 .tool_result(result),
    //                 to: &checkpoint.state
    //             )

    //             try await recordToolResult(
    //                 result
    //             )

    //             try await appendRunEvent(
    //                 .init(
    //                     kind: .tool_denied,
    //                     iteration: checkpoint.state.iteration,
    //                     toolCallID: toolCall.id,
    //                     toolName: toolCall.name,
    //                     summary: "denied by execution policy"
    //                 ),
    //                 to: &checkpoint
    //             )

    //             try await saveCheckpoint(
    //                 &checkpoint
    //             )

    //         case .needs_human_review:
    //             let decision = try await resolveApprovalDecision(
    //                 for: preflight,
    //                 requirement: requirement
    //             )

    //             switch decision {
    //             case .approved:
    //                 try await appendRunEvent(
    //                     .init(
    //                         kind: .tool_approved,
    //                         iteration: checkpoint.state.iteration,
    //                         toolCallID: toolCall.id,
    //                         toolName: toolCall.name,
    //                         summary: "approved"
    //                     ),
    //                     to: &checkpoint
    //                 )

    //                 let result = await executeApprovedToolCall(
    //                     toolCall
    //                 )

    //                 appendToolResultBlock(
    //                     .tool_result(result),
    //                     to: &checkpoint.state
    //                 )

    //                 try await recordToolResult(
    //                     result
    //                 )

    //                 try await appendRunEvent(
    //                     .init(
    //                         kind: result.isError ? .tool_error : .tool_result,
    //                         iteration: checkpoint.state.iteration,
    //                         toolCallID: toolCall.id,
    //                         toolName: toolCall.name,
    //                         summary: result.isError
    //                             ? "tool execution failed"
    //                             : "tool executed"
    //                     ),
    //                     to: &checkpoint
    //                 )

    //                 try await saveCheckpoint(
    //                     &checkpoint
    //                 )

    //             case .denied:
    //                 let result = makeDeniedToolResult(
    //                     for: toolCall,
    //                     preflight: preflight,
    //                     requirement: requirement
    //                 )

    //                 appendToolResultBlock(
    //                     .tool_result(result),
    //                     to: &checkpoint.state
    //                 )

    //                 try await recordToolResult(
    //                     result
    //                 )

    //                 try await appendRunEvent(
    //                     .init(
    //                         kind: .tool_denied,
    //                         iteration: checkpoint.state.iteration,
    //                         toolCallID: toolCall.id,
    //                         toolName: toolCall.name,
    //                         summary: "denied after review"
    //                     ),
    //                     to: &checkpoint
    //                 )

    //                 try await saveCheckpoint(
    //                     &checkpoint
    //                 )

    //             case .needshuman:
    //                 let pendingApproval = PendingApproval(
    //                     toolCall: toolCall,
    //                     preflight: preflight,
    //                     requirement: requirement
    //                 )
    //                 let suspension = AgentSuspension.approval(
    //                     pendingApproval
    //                 )

    //                 checkpoint.suspend(
    //                     suspension
    //                 )

    //                 try await appendRunEvent(
    //                     .init(
    //                         kind: .pending_approval,
    //                         iteration: checkpoint.state.iteration,
    //                         toolCallID: toolCall.id,
    //                         toolName: toolCall.name,
    //                         summary: preflight.summary
    //                     ),
    //                     to: &checkpoint
    //                 )

    //                 try await saveCheckpoint(
    //                     &checkpoint
    //                 )

    //                 return .result(
    //                     try suspendedResult(
    //                         from: checkpoint
    //                     )
    //                 )
    //             }
    //         }
    //     }

    //     checkpoint.phase = .ready_for_model
    //     checkpoint.lastResponse = nil
    //     checkpoint.clearSuspension()

    //     try await saveCheckpoint(
    //         &checkpoint
    //     )

    //     return .continueLoop(checkpoint)
    // }
}
