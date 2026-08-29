import AgenticExecution

public extension ToolLoopExecutor {
    func resume(
        _ checkpoint: AgentHistoryCheckpoint,
        approvalDecision: ApprovalDecision,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        var checkpoint = checkpoint

        guard let pendingApproval = checkpoint.resolvedSuspension?.pendingApproval else {
            throw AgentHistoryError.corruptedCheckpoint(
                "checkpoint is not awaiting approval"
            )
        }

        switch approvalDecision {
        case .approved:
            try await appendRunEvent(
                .init(
                    kind: .tool_approved,
                    iteration: checkpoint.state.iteration,
                    toolCallID: pendingApproval.toolCall.id,
                    toolName: pendingApproval.toolCall.name,
                    summary: metadata["summary"] ?? "approved after suspended review"
                ),
                to: &checkpoint
            )

            let result = await executeApprovedToolCall(
                pendingApproval.toolCall
            )

            try await appendToolResult(
                result,
                for: pendingApproval.toolCall,
                disposition: result.isError ? .failed_execution : .executed,
                to: &checkpoint,
                summary: result.isError
                    ? "tool execution failed after suspended approval"
                    : "tool executed after suspended approval"
            )

            checkpoint.clearSuspension()

            if pendingApproval.preflight.risk.isMutating {
                try await appendSkippedSiblings(
                    after: pendingApproval.toolCall.id,
                    to: &checkpoint,
                    disposition: .skipped_after_mutation,
                    reason: staleMutationSiblingReason
                )

                finishToolBatch(
                    on: &checkpoint
                )
            } else {
                checkpoint.phase = .processing_tool_calls
            }

            try await saveCheckpoint(
                &checkpoint
            )

            return try await runLoop(
                from: checkpoint
            )

        case .denied:
            let result = makeDeniedToolResult(
                for: pendingApproval.toolCall,
                preflight: pendingApproval.preflight,
                requirement: pendingApproval.requirement
            )

            try await appendToolResult(
                result,
                for: pendingApproval.toolCall,
                disposition: .skipped_after_denial,
                to: &checkpoint,
                summary: metadata["summary"] ?? "denied after suspended review"
            )

            try await appendRunEvent(
                .init(
                    kind: .tool_denied,
                    iteration: checkpoint.state.iteration,
                    toolCallID: pendingApproval.toolCall.id,
                    toolName: pendingApproval.toolCall.name,
                    summary: metadata["summary"] ?? "denied after suspended review"
                ),
                to: &checkpoint
            )

            try await appendSkippedSiblings(
                after: pendingApproval.toolCall.id,
                to: &checkpoint,
                disposition: .skipped_after_denial,
                reason: deniedSiblingReason
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

        case .skipped:
            let result = makeSkippedToolResult(
                for: pendingApproval.toolCall,
                summary: metadata["summary"] ?? "skipped after suspended review"
            )

            try await appendToolResult(
                result,
                for: pendingApproval.toolCall,
                disposition: .skipped_by_user,
                to: &checkpoint,
                summary: metadata["summary"] ?? "skipped after suspended review"
            )

            try await appendRunEvent(
                .init(
                    kind: .tool_skipped,
                    iteration: checkpoint.state.iteration,
                    toolCallID: pendingApproval.toolCall.id,
                    toolName: pendingApproval.toolCall.name,
                    summary: metadata["summary"] ?? "skipped after suspended review"
                ),
                to: &checkpoint
            )

            checkpoint.clearSuspension()
            checkpoint.phase = .processing_tool_calls

            try await saveCheckpoint(
                &checkpoint
            )

            return try await runLoop(
                from: checkpoint
            )

        case .needshuman:
            return try suspendedResult(
                from: checkpoint
            )
        }
    }
}
