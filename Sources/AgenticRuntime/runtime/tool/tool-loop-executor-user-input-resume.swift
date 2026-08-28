import Agentic

extension ToolLoopExecutor {
    func resumeWithUserInput(
        _ checkpoint: AgentHistoryCheckpoint,
        userInput: String,
        metadata: [String: String]
    ) async throws -> AgentRunResult {
        try await resumeWithUserInput(
            checkpoint,
            answer: .text(
                userInput
            ),
            metadata: metadata
        )
    }

    func resumeWithUserInput(
        _ checkpoint: AgentHistoryCheckpoint,
        answer: UserInputAnswer,
        metadata: [String: String]
    ) async throws -> AgentRunResult {
        var checkpoint = checkpoint

        guard checkpoint.phase == .suspended
            || checkpoint.phase == .awaiting_approval
        else {
            throw AgentHistoryError.sessionNotAwaitingUserInput(
                checkpoint.id
            )
        }

        guard let suspension = checkpoint.resolvedSuspension else {
            throw AgentHistoryError.corruptedCheckpoint(
                "resume with user input without suspension payload"
            )
        }

        guard case .user_input(let pendingUserInput) = suspension.reason else {
            throw AgentHistoryError.sessionNotAwaitingUserInput(
                checkpoint.id
            )
        }

        guard let toolCallID = suspension.metadata["toolCallID"] else {
            throw AgentHistoryError.corruptedCheckpoint(
                "user-input suspension without tool call id"
            )
        }

        let toolName = suspension.metadata["toolName"]
            ?? ClarifyWithUserTool.identifier.rawValue

        let normalizedAnswer = try normalizedUserInputAnswer(
            answer,
            for: pendingUserInput
        )

        var payloadMetadata = pendingUserInput.metadata

        payloadMetadata.merge(
            suspension.metadata
        ) { _, new in
            new
        }

        payloadMetadata.merge(
            metadata
        ) { _, new in
            new
        }

        let result = AgentToolResult(
            toolCallID: toolCallID,
            name: toolName,
            output: try JSONToolBridge.encode(
                UserInputResumePayload(
                    kind: "user_input_received",
                    prompt: pendingUserInput.prompt,
                    answer: normalizedAnswer,
                    metadata: payloadMetadata
                )
            ),
            isError: false
        )

        let toolCall = AgentToolCall(
            id: toolCallID,
            name: toolName,
            input: .object([:])
        )

        try await appendToolResult(
            result,
            for: toolCall,
            disposition: .executed,
            to: &checkpoint,
            summary: "user input received"
        )

        try await appendSkippedSiblings(
            after: toolCallID,
            to: &checkpoint,
            disposition: .skipped_after_user_input,
            reason: userInputSiblingReason
        )

        finishToolBatch(
            on: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        return try await runLoop(
            from: checkpoint
        )
    }
}
