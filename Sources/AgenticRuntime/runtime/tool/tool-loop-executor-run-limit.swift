extension ToolLoopExecutor {
    func runLimitExhaustion(
        in checkpoint: AgentHistoryCheckpoint
    ) -> AgentRunLimitExhaustion? {
        guard let limit = checkpoint.runLimits.iterations,
              checkpoint.state.iteration >= limit
        else {
            return nil
        }

        return .iterations(
            limit: limit,
            consumed: checkpoint.state.iteration
        )
    }

    func suspendForRunLimit(
        _ exhaustion: AgentRunLimitExhaustion,
        checkpoint: inout AgentHistoryCheckpoint
    ) async throws -> AgentRunResult {
        let suspension = AgentSuspension.run_limit(
            exhaustion
        )

        checkpoint.failure = nil
        checkpoint.suspend(
            suspension
        )

        try await appendRunEvent(
            .init(
                kind: .run_limit_reached,
                iteration: checkpoint.state.iteration,
                summary: exhaustion.summary
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        return try suspendedResult(
            from: checkpoint
        )
    }

    func resumeFromRunLimit(
        _ checkpoint: AgentHistoryCheckpoint,
        resolution: AgentRunLimitResolution,
        metadata: [String: String]
    ) async throws -> AgentRunResult {
        var checkpoint = checkpoint
        _ = metadata

        guard checkpoint.phase == .suspended,
              let suspension = checkpoint.resolvedSuspension,
              case .run_limit(let exhaustion) = suspension.reason
        else {
            throw AgentHistoryError.corruptedCheckpoint(
                "resume run limit without run-limit suspension"
            )
        }

        switch resolution {
        case .continue_with(let limits):
            checkpoint.runLimits = limits
            checkpoint.clearSuspension()

            try await appendRunEvent(
                .init(
                    kind: .run_limit_continued,
                    iteration: checkpoint.state.iteration,
                    summary: "Agent run limit continuation accepted."
                ),
                to: &checkpoint
            )

            try await saveCheckpoint(
                &checkpoint
            )

            return try await runLoop(
                from: checkpoint
            )

        case .stop:
            checkpoint.clearSuspension()
            checkpoint.phase = .interrupted
            checkpoint.failure = nil

            try await appendRunEvent(
                .init(
                    kind: .run_limit_stopped,
                    iteration: checkpoint.state.iteration,
                    summary: "Agent run stopped after reaching its run limit. \(exhaustion.summary)"
                ),
                to: &checkpoint
            )

            try await saveCheckpoint(
                &checkpoint
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
    }
}
