import Agentic

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
                interruption = await requestedInterruption()
                exhaustion = runLimitExhaustion(in: checkpoint)
            }

            switch flow.decide(
                checkpoint,
                interruption: interruption,
                exhaustion: exhaustion
            ) {
            case .model:
                checkpoint = try await performModelTurn(
                    from: checkpoint
                )

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
                return try result(
                    for: checkpoint
                )
            }
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
