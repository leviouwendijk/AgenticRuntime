import Agentic
import AgenticContext

extension AgentLoop {
    /// Decides what an Agent run does next. It never performs work: the loop
    /// carries out each decision and asks again.
    struct Flow: Sendable {
        enum Decision {
            /// Send the next model turn.
            case model
            /// Execute the function calls the last response asked for.
            case calls
            /// Stop at the operator's request.
            case interrupt(Run.Interruption)
            /// Pause until the operator extends or stops the run.
            case runLimit(AgentRunLimitExhaustion)
            /// The checkpoint is terminal or waiting; report it.
            case finish
        }

        /// Conversational control: call the model, run the calls it asks for,
        /// repeat until it answers without calls.
        static let conversational = Flow()

        func decide(
            _ checkpoint: AgentExecutor.Checkpoint,
            interruption: Run.Interruption?,
            exhaustion: AgentRunLimitExhaustion?
        ) -> Decision {
            switch checkpoint.phase {
            case .ready_for_model:
                if let interruption {
                    return .interrupt(interruption)
                }
                if let exhaustion {
                    return .runLimit(exhaustion)
                }
                return .model

            case .processing_tool_calls:
                return .calls

            case .receiving_model_response,
                 .suspended,
                 .awaiting_approval,
                 .interrupted,
                 .failed,
                 .completed:
                return .finish
            }
        }

        /// How the rest of a batch is handled after a call runs: nil lets the
        /// remaining calls run; a disposition skips them. A mutation may have
        /// changed what those calls were based on.
        func remainder(
            afterExecuting preflight: ToolPreflight
        ) -> AgentToolUseDisposition? {
            preflight.mayInvalidateSourceState ? .skipped_after_mutation : nil
        }

        /// A denied call ends its batch; the model re-plans with the denial.
        var remainderAfterDenial: AgentToolUseDisposition {
            .skipped_after_denial
        }

        /// Where a model response leaves the run.
        func phase(
            after response: AgentResponse,
            calls: [FunctionCall]
        ) -> AgentExecutor.Phase {
            response.stopReason == .tool_use && !calls.isEmpty
                ? .processing_tool_calls
                : .completed
        }
    }

    func runLoop(
        from initialCheckpoint: AgentExecutor.Checkpoint
    ) async throws -> AgentExecutor.Result {
        var checkpoint = initialCheckpoint

        while true {
            var interruption: Run.Interruption?
            var exhaustion: AgentRunLimitExhaustion?
            if checkpoint.phase == .ready_for_model {
                try await applySteering(to: &checkpoint)
                interruption = await requestedInterruption()
                exhaustion = runLimitExhaustion(in: checkpoint)
            }

            switch flow.decide(
                checkpoint,
                interruption: interruption,
                exhaustion: exhaustion
            ) {
            case .model:
                do {
                    checkpoint = try await performModelTurn(
                        from: checkpoint
                    )
                } catch ContextInferenceError.inputBudgetExceeded(let estimated, let maximum) {
                    // Nothing was sent: pause where the run is, resumable
                    // once the operator compacts, instead of failing it.
                    return try await suspendForRunLimit(
                        .context(
                            estimatedInputTokens: estimated,
                            limit: maximum,
                            compactable: await compactableTokens(in: checkpoint)
                        ),
                        checkpoint: &checkpoint
                    )
                }

            case .calls:
                switch try await processToolCalls(from: checkpoint) {
                case .continueLoop(let updated):
                    checkpoint = updated
                case .result(let result):
                    return result
                }

            case .interrupt(let request):
                return try await interrupt(
                    checkpoint,
                    mode: request.mode,
                    reason: request.reason
                )

            case .runLimit(let exhaustion):
                return try await suspendForRunLimit(
                    exhaustion,
                    checkpoint: &checkpoint
                )

            case .finish:
                // Steering that arrived with the final answer is not
                // stranded: the run takes one more turn for it.
                if checkpoint.phase == .completed, await runControl.hasSteering {
                    checkpoint.phase = .ready_for_model
                    continue
                }
                return try result(
                    for: checkpoint
                )
            }
        }
    }

    /// Operator messages join the conversation before the next model
    /// request, after the previous turn's tool outcomes are recorded.
    func applySteering(
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let messages = await runControl.takeSteering()
        guard !messages.isEmpty else { return }
        for message in messages {
            checkpoint.state.messages.append(message)
            try await recordMessage(message)
            try await appendRunEvent(
                .init(
                    kind: .input_applied,
                    iteration: checkpoint.state.iteration,
                    messageID: message.id,
                    summary: "operator input joined the run"
                ),
                to: &checkpoint
            )
        }
    }

    /// The run's result for a checkpoint the flow has finished with.
    func result(
        for checkpoint: AgentExecutor.Checkpoint
    ) throws -> AgentExecutor.Result {
        switch checkpoint.phase {
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
                costRecord: checkpoint.costRecord,
                invocations: checkpoint.invocations
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
                costRecord: checkpoint.costRecord,
                invocations: checkpoint.invocations
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
                costRecord: checkpoint.costRecord,
                invocations: checkpoint.invocations
            )

        case .receiving_model_response:
            throw AgentStreamingError.receivingModelResponseCheckpoint(
                checkpoint.id
            )

        case .ready_for_model,
             .processing_tool_calls:
            throw AgentHistoryError.corruptedCheckpoint(
                "run finished in non-terminal phase \(checkpoint.phase.rawValue)"
            )
        }
    }
}
