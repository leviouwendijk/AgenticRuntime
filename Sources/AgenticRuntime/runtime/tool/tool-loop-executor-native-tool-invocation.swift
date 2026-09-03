import Agentic
import AgenticExecution

extension ToolLoopExecutor {
    func applyNativeToolInvocations(
        _ invocations: [ToolInvocation.Result],
        to checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        for invocation in invocations {
            guard let result = invocation.toolResult else {
                continue
            }

            let call = invocation.review.call
            let response = AgentResponse(
                message: AgentMessage(
                    role: .assistant,
                    content: AgentContent(
                        blocks: [
                            .tool_call(
                                call
                            ),
                        ]
                    )
                ),
                stopReason: .tool_use
            )

            checkpoint.state.messages.append(
                response.message
            )
            checkpoint.lastResponse = response
            storeToolBatch(
                AgentToolUseBatch(
                    response: response
                ),
                to: &checkpoint
            )

            try await recordMessage(
                response.message
            )

            try await appendRunEvent(
                .init(
                    kind: .assistant_response,
                    iteration: checkpoint.state.iteration,
                    messageID: response.message.id,
                    summary: AgentStopReason.tool_use.rawValue
                ),
                to: &checkpoint
            )

            try await recordToolCall(
                call
            )

            markToolPreflight(
                invocation.review.preflight,
                for: call,
                on: &checkpoint
            )

            try await appendRunEvent(
                .init(
                    kind: .tool_preflight,
                    iteration: checkpoint.state.iteration,
                    toolCallID: call.id,
                    toolName: call.name,
                    summary: invocation.review.preflight.summary
                ),
                to: &checkpoint
            )

            let disposition: AgentToolUseDisposition
            let summary: String

            switch invocation.decision {
            case .approved:
                disposition = result.isError
                    ? .failed_execution
                    : .executed
                summary = result.isError
                    ? "native tool execution failed"
                    : "native tool executed"

                try await appendRunEvent(
                    .init(
                        kind: .tool_approved,
                        iteration: checkpoint.state.iteration,
                        toolCallID: call.id,
                        toolName: call.name,
                        summary: "approved"
                    ),
                    to: &checkpoint
                )

            case .denied:
                disposition = .skipped_after_denial
                summary = "native tool denied"

                try await appendRunEvent(
                    .init(
                        kind: .tool_denied,
                        iteration: checkpoint.state.iteration,
                        toolCallID: call.id,
                        toolName: call.name,
                        summary: summary
                    ),
                    to: &checkpoint
                )

            case .skipped:
                disposition = .skipped_by_user
                summary = "native tool skipped"

                try await appendRunEvent(
                    .init(
                        kind: .tool_skipped,
                        iteration: checkpoint.state.iteration,
                        toolCallID: call.id,
                        toolName: call.name,
                        summary: summary
                    ),
                    to: &checkpoint
                )

            case .needshuman:
                continue
            }

            try await appendToolResult(
                result,
                for: call,
                disposition: disposition,
                to: &checkpoint,
                summary: summary
            )

            finishToolBatch(
                on: &checkpoint
            )
        }
    }

    func suspendForNativeApproval(
        _ review: ToolInvocation.Review,
        invocations: [ToolInvocation.Result],
        checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        checkpoint.state.iteration += 1

        try await applyNativeToolInvocations(
            invocations,
            to: &checkpoint
        )

        let response = AgentResponse(
            message: AgentMessage(
                role: .assistant,
                content: AgentContent(
                    blocks: [
                        .tool_call(
                            review.call
                        ),
                    ]
                )
            ),
            stopReason: .tool_use
        )
        let pendingApproval = PendingApproval(
            toolCall: review.call,
            preflight: review.preflight,
            requirement: review.requirement
        )

        checkpoint.state.messages.append(
            response.message
        )
        checkpoint.lastResponse = response
        checkpoint.partialResponse = nil

        storeToolBatch(
            AgentToolUseBatch(
                response: response
            ),
            to: &checkpoint
        )

        markToolPreflight(
            review.preflight,
            for: review.call,
            on: &checkpoint
        )

        suspendToolBatch(
            for: review.call,
            disposition: .suspended_for_approval,
            on: &checkpoint
        )

        checkpoint.suspend(
            .approval(
                pendingApproval
            )
        )

        try await recordMessage(
            response.message
        )
        try await recordToolCall(
            review.call
        )

        try await appendRunEvent(
            .init(
                kind: .assistant_response,
                iteration: checkpoint.state.iteration,
                messageID: response.message.id,
                summary: AgentStopReason.tool_use.rawValue
            ),
            to: &checkpoint
        )

        try await appendRunEvent(
            .init(
                kind: .tool_preflight,
                iteration: checkpoint.state.iteration,
                toolCallID: review.call.id,
                toolName: review.call.name,
                summary: review.preflight.summary
            ),
            to: &checkpoint
        )

        try await appendRunEvent(
            .init(
                kind: .pending_approval,
                iteration: checkpoint.state.iteration,
                toolCallID: review.call.id,
                toolName: review.call.name,
                summary: review.preflight.summary
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )
    }

    func finishNativeExposureBoundary(
        invocations: [ToolInvocation.Result],
        checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        checkpoint.state.iteration += 1

        try await applyNativeToolInvocations(
            invocations,
            to: &checkpoint
        )

        checkpoint.partialResponse = nil
        checkpoint.lastResponse = nil
        checkpoint.clearSuspension()
        checkpoint.phase = .ready_for_model

        try await saveCheckpoint(
            &checkpoint
        )
    }
}
