import AgenticExecution

extension ToolLoopExecutor {
    func processToolCalls(
        from checkpoint: AgentHistoryCheckpoint
    ) async throws -> ToolProcessingOutcome {
        var checkpoint = checkpoint

        guard let response = checkpoint.lastResponse else {
            throw AgentHistoryError.corruptedCheckpoint(
                "processing tool calls without last response"
            )
        }

        var batch = toolBatch(
            from: response,
            checkpoint: checkpoint
        )
        storeToolBatch(
            batch,
            to: &checkpoint
        )

        guard !batch.toolCalls.isEmpty else {
            finishToolBatch(
                on: &checkpoint
            )

            try await saveCheckpoint(
                &checkpoint
            )

            return .continueLoop(checkpoint)
        }

        for record in batch.records where !record.isTerminal {
            let toolCall = record.toolCall

            if toolCall.name == ClarifyWithUserTool.identifier.rawValue {
                suspendToolBatch(
                    for: toolCall,
                    disposition: .suspended_for_user_input,
                    on: &checkpoint
                )

                return try await suspendForUserInput(
                    toolCall,
                    checkpoint: &checkpoint
                )
            }

            try await recordToolCall(
                toolCall
            )

            let preflight: ToolPreflight

            do {
                preflight = try await toolRegistry.preflight(
                    toolCall,
                    workspace: workspace
                )
            } catch {
                let result = makeToolErrorResult(
                    for: toolCall,
                    error: error
                )

                try await appendToolResult(
                    result,
                    for: toolCall,
                    disposition: .failed_preflight,
                    to: &checkpoint,
                    summary: localizedDescription(
                        for: error
                    )
                )

                try await saveCheckpoint(
                    &checkpoint
                )

                batch = checkpoint.toolBatch ?? batch
                continue
            }

            markToolPreflight(
                preflight,
                for: toolCall,
                on: &checkpoint
            )

            try await appendRunEvent(
                .init(
                    kind: .tool_preflight,
                    iteration: checkpoint.state.iteration,
                    toolCallID: toolCall.id,
                    toolName: toolCall.name,
                    summary: preflight.summary
                ),
                to: &checkpoint
            )

            let requirement = ToolExecutionPolicy(
                autonomyMode: configuration.autonomyMode,
                limits: configuration.executionLimits
            ).evaluate(
                preflight
            )

            switch requirement {
            case .no_approval_needed:
                try await appendRunEvent(
                    .init(
                        kind: .tool_approved,
                        iteration: checkpoint.state.iteration,
                        toolCallID: toolCall.id,
                        toolName: toolCall.name,
                        summary: "approved"
                    ),
                    to: &checkpoint
                )

                let result = await executeApprovedToolCall(
                    toolCall
                )

                try await appendToolResult(
                    result,
                    for: toolCall,
                    disposition: result.isError ? .failed_execution : .executed,
                    to: &checkpoint,
                    summary: result.isError
                        ? "tool execution failed"
                        : "tool executed"
                )

                if preflight.risk.isMutating {
                    try await appendSkippedSiblings(
                        after: toolCall.id,
                        to: &checkpoint,
                        disposition: .skipped_after_mutation,
                        reason: staleMutationSiblingReason
                    )

                    finishToolBatch(
                        on: &checkpoint
                    )

                    try await saveCheckpoint(
                        &checkpoint
                    )

                    return .continueLoop(checkpoint)
                }

                try await saveCheckpoint(
                    &checkpoint
                )

                batch = checkpoint.toolBatch ?? batch

            case .denied_forbidden:
                let result = makeDeniedToolResult(
                    for: toolCall,
                    preflight: preflight,
                    requirement: requirement
                )

                try await appendToolResult(
                    result,
                    for: toolCall,
                    disposition: .failed_preflight,
                    to: &checkpoint,
                    summary: "denied by execution policy"
                )

                try await appendRunEvent(
                    .init(
                        kind: .tool_denied,
                        iteration: checkpoint.state.iteration,
                        toolCallID: toolCall.id,
                        toolName: toolCall.name,
                        summary: "denied by execution policy"
                    ),
                    to: &checkpoint
                )

                try await appendSkippedSiblings(
                    after: toolCall.id,
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

                return .continueLoop(checkpoint)

            case .needs_human_review:
                let decision = try await resolveApprovalDecision(
                    for: preflight,
                    requirement: requirement
                )

                switch decision {
                case .approved:
                    try await appendRunEvent(
                        .init(
                            kind: .tool_approved,
                            iteration: checkpoint.state.iteration,
                            toolCallID: toolCall.id,
                            toolName: toolCall.name,
                            summary: "approved"
                        ),
                        to: &checkpoint
                    )

                    let result = await executeApprovedToolCall(
                        toolCall
                    )

                    try await appendToolResult(
                        result,
                        for: toolCall,
                        disposition: result.isError ? .failed_execution : .executed,
                        to: &checkpoint,
                        summary: result.isError
                            ? "tool execution failed"
                            : "tool executed"
                    )

                    if preflight.risk.isMutating {
                        try await appendSkippedSiblings(
                            after: toolCall.id,
                            to: &checkpoint,
                            disposition: .skipped_after_mutation,
                            reason: staleMutationSiblingReason
                        )

                        finishToolBatch(
                            on: &checkpoint
                        )

                        try await saveCheckpoint(
                            &checkpoint
                        )

                        return .continueLoop(checkpoint)
                    }

                    try await saveCheckpoint(
                        &checkpoint
                    )

                    batch = checkpoint.toolBatch ?? batch

                case .denied:
                    let result = makeDeniedToolResult(
                        for: toolCall,
                        preflight: preflight,
                        requirement: requirement
                    )

                    try await appendToolResult(
                        result,
                        for: toolCall,
                        disposition: .skipped_after_denial,
                        to: &checkpoint,
                        summary: "denied after review"
                    )

                    try await appendRunEvent(
                        .init(
                            kind: .tool_denied,
                            iteration: checkpoint.state.iteration,
                            toolCallID: toolCall.id,
                            toolName: toolCall.name,
                            summary: "denied after review"
                        ),
                        to: &checkpoint
                    )

                    try await appendSkippedSiblings(
                        after: toolCall.id,
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

                    return .continueLoop(checkpoint)

                case .skipped:
                    let result = makeSkippedToolResult(
                        for: toolCall
                    )

                    try await appendToolResult(
                        result,
                        for: toolCall,
                        disposition: .skipped_by_user,
                        to: &checkpoint,
                        summary: "skipped after review"
                    )

                    try await appendRunEvent(
                        .init(
                            kind: .tool_skipped,
                            iteration: checkpoint.state.iteration,
                            toolCallID: toolCall.id,
                            toolName: toolCall.name,
                            summary: "skipped after review"
                        ),
                        to: &checkpoint
                    )

                    try await saveCheckpoint(
                        &checkpoint
                    )

                    batch = checkpoint.toolBatch ?? batch

                case .needshuman:
                    let pendingApproval = PendingApproval(
                        toolCall: toolCall,
                        preflight: preflight,
                        requirement: requirement
                    )

                    suspendToolBatch(
                        for: toolCall,
                        disposition: .suspended_for_approval,
                        on: &checkpoint
                    )

                    checkpoint.suspend(
                        .approval(
                            pendingApproval
                        )
                    )

                    try await appendRunEvent(
                        .init(
                            kind: .pending_approval,
                            iteration: checkpoint.state.iteration,
                            toolCallID: toolCall.id,
                            toolName: toolCall.name,
                            summary: preflight.summary
                        ),
                        to: &checkpoint
                    )

                    try await saveCheckpoint(
                        &checkpoint
                    )

                    return .result(
                        try suspendedResult(
                            from: checkpoint
                        )
                    )
                }
            }
        }

        finishToolBatch(
            on: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        return .continueLoop(checkpoint)
    }
}
