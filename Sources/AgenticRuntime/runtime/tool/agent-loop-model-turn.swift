import Agentic
import AgenticIO
import Workspace
import AgenticStandard
import Primitives

extension AgentLoop {
    func processToolCalls(
        from checkpoint: AgentExecutor.Checkpoint
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

        guard !batch.functionCalls.isEmpty else {
            finishToolBatch(
                on: &checkpoint
            )

            try await saveCheckpoint(
                &checkpoint
            )

            return .continueLoop(checkpoint)
        }

        if let delegated = try await processDelegatedBatch(from: checkpoint) {
            return delegated
        }

        for record in batch.records where !record.isTerminal {
            if record.isSuspended {
                return try await surfaceRetainedChild(
                    record.functionCall,
                    checkpoint: &checkpoint
                )
            }
            if let interruption = await requestedUrgentInterruption() {
                return .result(
                    try await interrupt(
                        checkpoint,
                        mode: interruption.mode,
                        reason: interruption.reason
                    )
                )
            }

            let functionCall = record.functionCall
            try begin_tool_invocation(
                call_id: functionCall.id,
                tool_name: functionCall.name,
                in: &checkpoint
            )

            try await recordFunctionCall(
                functionCall
            )

            // Semantic model functions are not installed Tools. A saved,
            // request-bound projection is required to invoke them.
            if let projection = checkpoint.lastAdvertisedCapabilities,
               let target = projection.target(named: functionCall.name) {
                switch target {
                case .program, .inference, .agent:
                    if let stopped = try await interruptionBeforeToolExecution(checkpoint) {
                        return stopped
                    }
                    do {
                        let resolver = CapabilityFunctionCallResolver(
                            dispatcher: await modelDispatcher(sessionID: checkpoint.id),
                            projection: projection,
                            journal: nil
                        )
                        let result = try await resolver.resolve(functionCall)
                        try await appendToolResult(
                            result,
                            for: functionCall,
                            disposition: result.isError ? .failed_execution : .executed,
                            to: &checkpoint,
                            summary: "semantic capability invoked"
                        )
                    } catch let suspension as RuntimeDelegatedChildSuspension {
                        try await mirrorDelegatedSuspension(
                            suspension,
                            checkpoint: &checkpoint
                        )
                        return .result(try suspendedResult(from: checkpoint))
                    } catch {
                        let result = try makeToolErrorResult(for: functionCall, error: error)
                        try await appendToolResult(
                            result,
                            for: functionCall,
                            disposition: .failed_execution,
                            to: &checkpoint,
                            summary: localizedDescription(for: error)
                        )
                    }
                    try await saveCheckpoint(&checkpoint)
                    batch = checkpoint.toolBatch ?? batch
                    continue

                case .tool:
                    break
                }
            }

            let invocation: ToolInvocation

            do {
                let available = await capabilityState.available
                guard checkpoint.lastAdvertisedTools?.contains(
                    ToolIdentifier(functionCall.name)
                ) == true,
                    available.tools.contains(ToolIdentifier(functionCall.name))
                else {
                    throw FunctionCallResolutionError
                        .toolNotVisible(
                            ToolIdentifier(functionCall.name)
                        )
                }

                invocation = try (await currentTools()).invocation(
                    for: functionCall
                )
            } catch {
                let result = try makeToolErrorResult(
                    for: functionCall,
                    error: error
                )

                try await appendToolResult(
                    result,
                    for: functionCall,
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

            let review: ToolInvocation.Review

            do {
                review = try await ToolExecutor(
                    registry: (await currentTools()),
                    policy: configuration.toolExecutionPolicy,
                    recovery: configuration.recovery
                ).review(
                    invocation,
                    context: await makeToolContext()
                )
            } catch {
                let result = try makeToolErrorResult(
                    for: functionCall,
                    error: error
                )

                try await appendToolResult(
                    result,
                    for: functionCall,
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

            let preflight = review.preflight

            markToolPreflight(
                preflight,
                for: functionCall,
                on: &checkpoint
            )

            try await appendRunEvent(
                .init(
                    kind: .tool_preflight,
                    iteration: checkpoint.state.iteration,
                    callID: functionCall.id,
                    toolName: functionCall.name,
                    summary: preflight.summary
                ),
                to: &checkpoint
            )

            if ToolIdentifier(functionCall.name) == Standard.Tools.ClarifyWithUser.identifier {
                suspendToolBatch(
                    for: functionCall,
                    disposition: .suspended_for_user_input,
                    on: &checkpoint
                )

                return try await suspendForUserInput(
                    invocation,
                    checkpoint: &checkpoint
                )
            }

            if ToolIdentifier(functionCall.name) == SystemIO.Tools.RequestPathGrant.identifier {
                if let stopped = try await interruptionBeforeToolExecution(checkpoint) {
                    return stopped
                }
                let execution = try await executeApprovedToolReview(
                    review
                )
                let result = execution.result

                if result.isError {
                    try await appendToolResult(
                        result,
                        for: functionCall,
                        disposition: .failed_execution,
                        recovery: execution.recovery,
                        observations: execution.observations,
                        to: &checkpoint,
                        summary: "workspace access request failed"
                    )

                    try await saveCheckpoint(
                        &checkpoint
                    )

                    batch = checkpoint.toolBatch ?? batch
                    continue
                }

                let request = try JSONCoding.default.decode(
                    WorkspaceAccessRequest.self,
                    from: result.output
                )

                suspendToolBatch(
                    for: functionCall,
                    disposition: .suspended_for_workspace_access,
                    on: &checkpoint
                )

                return try await suspendForWorkspaceAccess(
                    request,
                    functionCall: functionCall,
                    checkpoint: &checkpoint
                )
            }

            let requirement = review.requirement

            switch requirement {
            case .no_approval_needed:
                try await appendRunEvent(
                    .init(
                        kind: .tool_approved,
                        iteration: checkpoint.state.iteration,
                        callID: functionCall.id,
                        toolName: functionCall.name,
                        summary: "approved"
                    ),
                    to: &checkpoint
                )

                // Publish active execution before waiting for the tool result.
                try await saveCheckpoint(&checkpoint)

                if let stopped = try await interruptionBeforeToolExecution(checkpoint) {
                    return stopped
                }

                let execution = try await executeApprovedToolReview(
                    review
                )
                let result = execution.result

                try await appendToolResult(
                    result,
                    for: functionCall,
                    disposition: result.isError ? .failed_execution : .executed,
                    recovery: execution.recovery,
                    observations: execution.observations,
                    to: &checkpoint,
                    summary: result.isError
                        ? "tool execution failed"
                        : "tool executed"
                )

                if preflight.mayInvalidateSourceState {
                    try await appendSkippedSiblings(
                        after: functionCall.id,
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
                let result = try makeDeniedToolResult(
                    for: functionCall,
                    preflight: preflight,
                    requirement: requirement
                )

                try await appendToolResult(
                    result,
                    for: functionCall,
                    disposition: .failed_preflight,
                    to: &checkpoint,
                    summary: "denied by execution policy"
                )

                try await appendRunEvent(
                    .init(
                        kind: .tool_denied,
                        iteration: checkpoint.state.iteration,
                        callID: functionCall.id,
                        toolName: functionCall.name,
                        summary: "denied by execution policy"
                    ),
                    to: &checkpoint
                )

                try await appendSkippedSiblings(
                    after: functionCall.id,
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
                            callID: functionCall.id,
                            toolName: functionCall.name,
                            summary: "approved"
                        ),
                        to: &checkpoint
                    )

                    // Synchronous approvals also publish the running phase.
                    try await saveCheckpoint(&checkpoint)

                    if let stopped = try await interruptionBeforeToolExecution(checkpoint) {
                        return stopped
                    }

                    let execution = try await executeApprovedToolReview(
                        review
                    )
                    let result = execution.result

                    try await appendToolResult(
                        result,
                        for: functionCall,
                        disposition: result.isError ? .failed_execution : .executed,
                        recovery: execution.recovery,
                        observations: execution.observations,
                        to: &checkpoint,
                        summary: result.isError
                            ? "tool execution failed"
                            : "tool executed"
                    )

                    if preflight.mayInvalidateSourceState {
                        try await appendSkippedSiblings(
                            after: functionCall.id,
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
                    let result = try makeDeniedToolResult(
                        for: functionCall,
                        preflight: preflight,
                        requirement: requirement
                    )

                    try await appendToolResult(
                        result,
                        for: functionCall,
                        disposition: .skipped_after_denial,
                        to: &checkpoint,
                        summary: "denied after review"
                    )

                    try await appendRunEvent(
                        .init(
                            kind: .tool_denied,
                            iteration: checkpoint.state.iteration,
                            callID: functionCall.id,
                            toolName: functionCall.name,
                            summary: "denied after review"
                        ),
                        to: &checkpoint
                    )

                    try await appendSkippedSiblings(
                        after: functionCall.id,
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
                    let result = try makeSkippedToolResult(
                        for: functionCall
                    )

                    try await appendToolResult(
                        result,
                        for: functionCall,
                        disposition: .skipped_by_user,
                        to: &checkpoint,
                        summary: "skipped after review"
                    )

                    try await appendRunEvent(
                        .init(
                            kind: .tool_skipped,
                            iteration: checkpoint.state.iteration,
                            callID: functionCall.id,
                            toolName: functionCall.name,
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
                        functionCall: functionCall,
                        preflight: preflight,
                        requirement: requirement,
                        preparedOperation: review.preparedOperation
                    )

                    suspendToolBatch(
                        for: functionCall,
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
                            callID: functionCall.id,
                            toolName: functionCall.name,
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
