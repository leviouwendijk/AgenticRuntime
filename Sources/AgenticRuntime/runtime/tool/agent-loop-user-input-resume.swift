import Agentic
import AgenticStandard
import Primitives

extension AgentLoop {
    func resumeWithUserInput(
        _ checkpoint: AgentExecutor.Checkpoint,
        userInput: String,
        metadata: [String: String]
    ) async throws -> AgentExecutor.Result {
        try await resumeWithUserInput(
            checkpoint,
            reply: .text(
                userInput
            ),
            metadata: metadata
        )
    }

    func resumeWithUserInput(
        _ checkpoint: AgentExecutor.Checkpoint,
        reply: UserInputReply,
        metadata: [String: String]
    ) async throws -> AgentExecutor.Result {
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

        guard let callID = suspension.metadata["callID"] else {
            throw AgentHistoryError.corruptedCheckpoint(
                "user-input suspension without tool call id"
            )
        }

        let toolName = suspension.metadata["toolName"]
            ?? Standard.Tools.ClarifyWithUser.identifier.rawValue

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

        let result = FunctionCall.Response(
            call: FunctionCall.Reference(
                id: callID,
                name: toolName
            ),
            output: try JSONCoding.default.value(
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

        let functionCall = FunctionCall(
            id: callID,
            name: toolName,
            input: .object([:])
        )

        try await appendToolResult(
            result,
            for: functionCall,
            disposition: .executed,
            to: &checkpoint,
            summary: response.isSkipped
                ? "user input skipped"
                : "user input received"
        )

        try await appendSkippedSiblings(
            after: callID,
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
