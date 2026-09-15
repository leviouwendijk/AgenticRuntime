import Agentic
import AgenticTools

extension ToolLoopExecutor {
    func resumeWithUserInput(
        _ checkpoint: AgentHistoryCheckpoint,
        userInput: String,
        metadata: [String: String]
    ) async throws -> AgentRunResult {
        try await resumeWithUserInput(
            checkpoint,
            reply: .text(
                userInput
            ),
            metadata: metadata
        )
    }

    func resumeWithUserInput(
        _ checkpoint: AgentHistoryCheckpoint,
        reply: UserInputReply,
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

        guard case .user_input(let request) = suspension.reason else {
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

        let response = try UserInputResponse(
            reply,
            for: request
        )

        var payloadMetadata = request.metadata

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
                    kind: response.isSkipped
                        ? "user_input_skipped"
                        : "user_input_received",
                    prompt: request.prompt,
                    reply: response.reply,
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
            summary: response.isSkipped
                ? "user input skipped"
                : "user input received"
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
