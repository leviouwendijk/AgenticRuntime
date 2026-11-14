import Agentic
import Primitives

extension AgentLoop {
    func toolBatch(
        from response: AgentResponse,
        checkpoint: AgentExecutor.Checkpoint
    ) -> AgentToolUseBatch {
        checkpoint.toolBatch ?? AgentToolUseBatch(
            response: response
        )
    }

    func storeToolBatch(
        _ batch: AgentToolUseBatch,
        to checkpoint: inout AgentExecutor.Checkpoint
    ) {
        checkpoint.toolBatch = batch
        checkpoint.touch()
    }

    func finishToolBatch(
        on checkpoint: inout AgentExecutor.Checkpoint
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
        _ result: FunctionCall.Response,
        for functionCall: FunctionCall,
        disposition: AgentToolUseDisposition,
        recovery: Recovery.Record? = nil,
        observations: [ToolResultObservation] = [],
        to checkpoint: inout AgentExecutor.Checkpoint,
        summary: String,
        eventKind: Run.Event.State.Kind? = nil
    ) async throws {
        if var batch = checkpoint.toolBatch {
            batch.mark(
                callID: functionCall.id,
                disposition: disposition,
                result: result,
                recovery: recovery,
                observations: observations
            )
            batch.completeIfTerminal()
            checkpoint.toolBatch = batch
        }

        // The log keeps the full result; the conversation gets what the
        // model reads.
        try await recordToolResult(
            result
        )

        appendToolResultBlock(
            .result(await budgeted(result)),
            to: &checkpoint.state
        )

        try await appendRunEvent(
            .init(
                kind: eventKind ?? (result.isError ? .tool_error : .tool_result),
                iteration: checkpoint.state.iteration,
                callID: result.call.id,
                toolName: result.call.name,
                summary: summary
            ),
            to: &checkpoint
        )
    }

    func markToolPreflight(
        _ preflight: ToolPreflight,
        for functionCall: FunctionCall,
        on checkpoint: inout AgentExecutor.Checkpoint
    ) {
        guard var batch = checkpoint.toolBatch else {
            return
        }

        batch.mark(
            callID: functionCall.id,
            disposition: .preflighted,
            preflight: preflight
        )

        checkpoint.toolBatch = batch
        checkpoint.touch()
    }

    func suspendToolBatch(
        for functionCall: FunctionCall,
        disposition: AgentToolUseDisposition,
        on checkpoint: inout AgentExecutor.Checkpoint
    ) {
        guard var batch = checkpoint.toolBatch else {
            return
        }

        batch.mark(
            callID: functionCall.id,
            disposition: disposition
        )
        batch.suspend()

        checkpoint.toolBatch = batch
        checkpoint.touch()
    }

    func appendSkippedSiblings(
        after callID: String,
        to checkpoint: inout AgentExecutor.Checkpoint,
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

        for functionCall in batch.remaining(after: callID) {
            let result = makeSkippedToolResult(
                for: functionCall,
                disposition: disposition,
                reason: reason
            )

            try await appendToolResult(
                result,
                for: functionCall,
                disposition: disposition,
                to: &checkpoint,
                summary: "skipped sibling tool call"
            )
        }
    }

    func makeSkippedToolResult(
        for functionCall: FunctionCall,
        disposition: AgentToolUseDisposition,
        reason: String
    ) -> FunctionCall.Response {
        FunctionCall.Response(
            call: functionCall.reference,
            output: .object([
                "kind": .string("tool_error"),
                "callID": .string(functionCall.id),
                "toolName": .string(functionCall.name),
                "disposition": .string(disposition.rawValue),
                "message": .string(reason)
            ]),
            isError: true
        )
    }

    /// Why a sibling call was skipped, as told to the model.
    func siblingReason(
        for disposition: AgentToolUseDisposition
    ) -> String {
        switch disposition {
        case .skipped_after_mutation:
            staleMutationSiblingReason
        case .skipped_after_user_input:
            userInputSiblingReason
        case .skipped_after_workspace_access:
            workspaceAccessSiblingReason
        default:
            deniedSiblingReason
        }
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
