import Agentic
import AgenticExecution
import Primitives

extension ToolLoopExecutor {
    func toolBatch(
        from response: AgentResponse,
        checkpoint: AgentHistoryCheckpoint
    ) -> AgentToolUseBatch {
        checkpoint.toolBatch ?? AgentToolUseBatch(
            response: response
        )
    }

    func storeToolBatch(
        _ batch: AgentToolUseBatch,
        to checkpoint: inout AgentHistoryCheckpoint
    ) {
        checkpoint.toolBatch = batch
        checkpoint.touch()
    }

    func finishToolBatch(
        on checkpoint: inout AgentHistoryCheckpoint
    ) {
        if var batch = checkpoint.toolBatch {
            batch.completeIfTerminal()
            checkpoint.toolBatch = batch
        }

        checkpoint.clearToolBatch()
        checkpoint.lastResponse = nil
        checkpoint.clearSuspension()
        checkpoint.phase = .ready_for_model
    }

    func appendToolResult(
        _ result: AgentToolResult,
        for toolCall: AgentToolCall,
        disposition: AgentToolUseDisposition,
        to checkpoint: inout AgentHistoryCheckpoint,
        summary: String
    ) async throws {
        if var batch = checkpoint.toolBatch {
            batch.mark(
                toolCallID: toolCall.id,
                disposition: disposition,
                result: result
            )
            batch.completeIfTerminal()
            checkpoint.toolBatch = batch
        }

        appendToolResultBlock(
            .tool_result(result),
            to: &checkpoint.state
        )

        try await recordToolResult(
            result
        )

        try await appendRunEvent(
            .init(
                kind: result.isError ? .tool_error : .tool_result,
                iteration: checkpoint.state.iteration,
                toolCallID: result.toolCallID,
                toolName: result.name,
                summary: summary
            ),
            to: &checkpoint
        )
    }

    func markToolPreflight(
        _ preflight: ToolPreflight,
        for toolCall: AgentToolCall,
        on checkpoint: inout AgentHistoryCheckpoint
    ) {
        guard var batch = checkpoint.toolBatch else {
            return
        }

        batch.mark(
            toolCallID: toolCall.id,
            disposition: .preflighted,
            preflight: preflight
        )

        checkpoint.toolBatch = batch
        checkpoint.touch()
    }

    func suspendToolBatch(
        for toolCall: AgentToolCall,
        disposition: AgentToolUseDisposition,
        on checkpoint: inout AgentHistoryCheckpoint
    ) {
        guard var batch = checkpoint.toolBatch else {
            return
        }

        batch.mark(
            toolCallID: toolCall.id,
            disposition: disposition
        )
        batch.suspend()

        checkpoint.toolBatch = batch
        checkpoint.touch()
    }

    func appendSkippedSiblings(
        after toolCallID: String,
        to checkpoint: inout AgentHistoryCheckpoint,
        disposition: AgentToolUseDisposition,
        reason: String
    ) async throws {
        let batch: AgentToolUseBatch

        if let stored = checkpoint.toolBatch {
            batch = stored
        } else if let response = checkpoint.lastResponse {
            batch = AgentToolUseBatch(
                response: response
            )
            checkpoint.toolBatch = batch
        } else {
            throw AgentHistoryError.corruptedCheckpoint(
                "cannot skip sibling tool calls without a stored tool batch or last response"
            )
        }

        for toolCall in batch.remaining(after: toolCallID) {
            let result = makeSkippedToolResult(
                for: toolCall,
                disposition: disposition,
                reason: reason
            )

            try await appendToolResult(
                result,
                for: toolCall,
                disposition: disposition,
                to: &checkpoint,
                summary: "skipped sibling tool call"
            )
        }
    }

    func makeSkippedToolResult(
        for toolCall: AgentToolCall,
        disposition: AgentToolUseDisposition,
        reason: String
    ) -> AgentToolResult {
        AgentToolResult(
            toolCallID: toolCall.id,
            name: toolCall.name,
            output: .object([
                "kind": .string("tool_error"),
                "toolCallID": .string(toolCall.id),
                "toolName": .string(toolCall.name),
                "disposition": .string(disposition.rawValue),
                "message": .string(reason)
            ]),
            isError: true
        )
    }

    var staleMutationSiblingReason: String {
        "Skipped because a prior approved file mutation may have changed workspace state. Re-read the file and submit a fresh mutation if another change is still needed."
    }

    var deniedSiblingReason: String {
        "Skipped because a prior tool request in the same assistant response was denied. Re-submit only still-needed tool calls after receiving this result."
    }

    var userInputSiblingReason: String {
        "Skipped because a prior tool request paused for user input. Re-submit only still-needed tool calls after receiving the user's answer."
    }
}
