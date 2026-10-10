import Agentic
import Primitives

extension AgentLoop {
    func toolBatch(
        from response: AgentResponse,
        checkpoint: AgentRunner.Checkpoint
    ) -> AgentToolUseBatch {
        checkpoint.toolBatch ?? AgentToolUseBatch(
            response: response
        )
    }

    func storeToolBatch(
        _ batch: AgentToolUseBatch,
        to checkpoint: inout AgentRunner.Checkpoint
    ) {
        checkpoint.toolBatch = batch
        checkpoint.touch()
    }

    func finishToolBatch(
        on checkpoint: inout AgentRunner.Checkpoint
    ) {
        if var batch = checkpoint.toolBatch {
            batch.completeIfTerminal()
            checkpoint.toolBatch = batch
            checkpoint.archiveToolUses(
                batch.records
            )
        }

        checkpoint.clearToolBatch()
        checkpoint.lastResponse = nil
        checkpoint.clearSuspension()
        checkpoint.phase = .ready_for_model
    }

    func appendToolResult(
        _ result: ToolCall.Response,
        for toolCall: ToolCall,
        disposition: AgentToolUseDisposition,
        recovery: Recovery.Record? = nil,
        observations: [ToolResultObservation] = [],
        to checkpoint: inout AgentRunner.Checkpoint,
        summary: String
    ) async throws {
        if var batch = checkpoint.toolBatch {
            batch.mark(
                toolCallID: toolCall.id,
                disposition: disposition,
                result: result,
                recovery: recovery,
                observations: observations
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
                toolCallID: result.call.id,
                toolName: result.call.tool.rawValue,
                summary: summary
            ),
            to: &checkpoint
        )
    }

    func markToolPreflight(
        _ preflight: ToolPreflight,
        for toolCall: ToolCall,
        on checkpoint: inout AgentRunner.Checkpoint
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
        for toolCall: ToolCall,
        disposition: AgentToolUseDisposition,
        on checkpoint: inout AgentRunner.Checkpoint
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
        to checkpoint: inout AgentRunner.Checkpoint,
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
        for toolCall: ToolCall,
        disposition: AgentToolUseDisposition,
        reason: String
    ) -> ToolCall.Response {
        ToolCall.Response(
            call: toolCall.reference,
            output: .object([
                "kind": .string("tool_error"),
                "toolCallID": .string(toolCall.id),
                "toolName": .string(toolCall.tool.rawValue),
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

    var workspaceAccessSiblingReason: String {
        "Skipped because a prior tool request paused for workspace access resolution. Re-submit only still-needed tool calls after authority is resolved."
    }
}
