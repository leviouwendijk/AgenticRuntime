import Agentic

extension AgentLoop {
    func resume(
        _ checkpoint: AgentExecutor.Checkpoint,
        approvalDecision: ApprovalDecision,
        metadata: [String: String] = [:]
    ) async throws -> AgentExecutor.Result {
        try await resumeApproval(
            checkpoint,
            decision: approvalDecision,
            metadata: metadata
        )
    }
}

extension AgentLoop {
    func resumeApproval(
        _ checkpoint: AgentExecutor.Checkpoint,
        decision: ApprovalDecision,
        metadata: [String: String]
    ) async throws -> AgentExecutor.Result {
        var checkpoint = checkpoint

        guard let pendingApproval = checkpoint.resolvedSuspension?.pendingApproval else {
            throw AgentHistoryError.corruptedCheckpoint(
                "checkpoint is not awaiting approval"
            )
        }

        switch decision {
        case .approved:
            try await appendRunEvent(
                .init(
                    kind: .tool_approved,
                    iteration: checkpoint.state.iteration,
                    callID: pendingApproval.functionCall.id,
                    toolName: pendingApproval.functionCall.name,
                    summary: metadata["summary"] ?? "approved after suspended review"
                ),
                to: &checkpoint
            )

            checkpoint.clearSuspension()
            checkpoint.phase = .processing_tool_calls
            try await saveCheckpoint(&checkpoint)

            if let interruption = await requestedUrgentInterruption() {
                return try await interrupt(
                    checkpoint,
                    mode: interruption.mode,
                    reason: interruption.reason
                )
            }

            let execution = try await executeApprovedCall(
                pendingApproval,
                advertisedTools: checkpoint.lastAdvertisedTools
            )
            let result = execution.result

            try await appendToolResult(
                result,
                for: pendingApproval.functionCall,
                disposition: result.isError ? .failed_execution : .executed,
                recovery: execution.recovery,
                observations: execution.observations,
                to: &checkpoint,
                summary: result.isError
                    ? "tool execution failed after suspended approval"
                    : "tool executed after suspended approval"
            )

            checkpoint.clearSuspension()

            if pendingApproval.preflight.mayInvalidateSourceState {
                try await appendSkippedSiblings(
                    after: pendingApproval.functionCall.id,
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
            let result = try makeDeniedToolResult(
                for: pendingApproval.functionCall,
                preflight: pendingApproval.preflight,
                requirement: pendingApproval.requirement
            )

            try await appendToolResult(
                result,
                for: pendingApproval.functionCall,
                disposition: .skipped_after_denial,
                to: &checkpoint,
                summary: metadata["summary"] ?? "denied after suspended review"
            )

            try await appendRunEvent(
                .init(
                    kind: .tool_denied,
                    iteration: checkpoint.state.iteration,
                    callID: pendingApproval.functionCall.id,
                    toolName: pendingApproval.functionCall.name,
                    summary: metadata["summary"] ?? "denied after suspended review"
                ),
                to: &checkpoint
            )

            try await appendSkippedSiblings(
                after: pendingApproval.functionCall.id,
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
            let result = try makeSkippedToolResult(
                for: pendingApproval.functionCall,
                summary: metadata["summary"] ?? "skipped after suspended review"
            )

            try await appendToolResult(
                result,
                for: pendingApproval.functionCall,
                disposition: .skipped_by_user,
                to: &checkpoint,
                summary: metadata["summary"] ?? "skipped after suspended review"
            )

            try await appendRunEvent(
                .init(
                    kind: .tool_skipped,
                    iteration: checkpoint.state.iteration,
                    callID: pendingApproval.functionCall.id,
                    toolName: pendingApproval.functionCall.name,
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
