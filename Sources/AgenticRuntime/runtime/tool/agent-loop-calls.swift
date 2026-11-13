import Agentic
import AgenticIO
import AgenticStandard
import Primitives
import Workspace

extension AgentLoop {
    /// What one function call leaves for the rest of its batch.
    enum CallOutcome {
        /// The next call in the batch runs.
        case next
        /// The remaining calls were skipped; the run continues with a model turn.
        case endBatch
        /// The run suspends or stops with this result.
        case stop(AgentExecutor.Result)
    }

    func processToolCalls(
        from checkpoint: AgentExecutor.Checkpoint
    ) async throws -> ToolProcessingOutcome {
        var checkpoint = checkpoint

        guard let response = checkpoint.lastResponse else {
            throw AgentHistoryError.corruptedCheckpoint(
                "processing tool calls without last response"
            )
        }

        let batch = toolBatch(
            from: response,
            checkpoint: checkpoint
        )
        storeToolBatch(
            batch,
            to: &checkpoint
        )

        if !batch.functionCalls.isEmpty {
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
                if let stopped = try await interruptionBeforeToolExecution(checkpoint) {
                    return .result(stopped)
                }

                switch try await dispatch(record.functionCall, checkpoint: &checkpoint) {
                case .next:
                    continue
                case .endBatch:
                    return try await endBatch(&checkpoint)
                case .stop(let result):
                    return .result(result)
                }
            }
        }

        return try await endBatch(&checkpoint)
    }

    private func endBatch(
        _ checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> ToolProcessingOutcome {
        finishToolBatch(
            on: &checkpoint
        )
        try await saveCheckpoint(
            &checkpoint
        )
        return .continueLoop(checkpoint)
    }

    /// Takes one call from the model through resolution, review, approval and
    /// execution.
    private func dispatch(
        _ functionCall: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> CallOutcome {
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
                return try await invokeCapability(
                    functionCall,
                    projection: projection,
                    checkpoint: &checkpoint
                )
            case .tool:
                break
            }
        }

        guard let invocation = try await resolve(functionCall, checkpoint: &checkpoint),
              let review = try await review(invocation, for: functionCall, checkpoint: &checkpoint)
        else {
            return .next
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

        if let outcome = try await interact(
            review,
            for: functionCall,
            checkpoint: &checkpoint
        ) {
            return outcome
        }

        switch review.requirement {
        case .no_approval_needed:
            return try await execute(
                review,
                for: functionCall,
                checkpoint: &checkpoint
            )

        case .denied_forbidden:
            return try await reject(
                functionCall,
                review: review,
                disposition: .failed_preflight,
                summary: "denied by execution policy",
                checkpoint: &checkpoint
            )

        case .needs_human_review:
            switch try await resolveApprovalDecision(
                for: preflight,
                requirement: review.requirement
            ) {
            case .approved:
                return try await execute(
                    review,
                    for: functionCall,
                    checkpoint: &checkpoint
                )

            case .denied:
                return try await reject(
                    functionCall,
                    review: review,
                    disposition: .skipped_after_denial,
                    summary: "denied after review",
                    checkpoint: &checkpoint
                )

            case .skipped:
                try await appendToolResult(
                    try makeSkippedToolResult(for: functionCall),
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
                try await saveCheckpoint(&checkpoint)
                return .next

            case .needshuman:
                suspendToolBatch(
                    for: functionCall,
                    disposition: .suspended_for_approval,
                    on: &checkpoint
                )
                checkpoint.suspend(
                    .approval(
                        PendingApproval(
                            functionCall: functionCall,
                            preflight: preflight,
                            requirement: review.requirement,
                            preparedOperation: review.preparedOperation
                        )
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
                try await saveCheckpoint(&checkpoint)
                return .stop(try suspendedResult(from: checkpoint))
            }
        }
    }

    /// Invokes a Program, Inference or Agent the model called by function name.
    private func invokeCapability(
        _ functionCall: FunctionCall,
        projection: ModelCapabilityProjection,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> CallOutcome {
        if let stopped = try await interruptionBeforeToolExecution(checkpoint) {
            return .stop(stopped)
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
            return .stop(try suspendedResult(from: checkpoint))
        } catch {
            try await appendToolResult(
                try makeToolErrorResult(for: functionCall, error: error),
                for: functionCall,
                disposition: .failed_execution,
                to: &checkpoint,
                summary: localizedDescription(for: error)
            )
        }

        try await saveCheckpoint(&checkpoint)
        return .next
    }

    /// Parses an advertised, still-available tool call. A failure is answered
    /// to the model and yields nil.
    private func resolve(
        _ functionCall: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> ToolInvocation? {
        do {
            let tool = ToolIdentifier(functionCall.name)
            let available = await capabilityState.available
            guard checkpoint.lastAdvertisedTools?.contains(tool) == true,
                  available.tools.contains(tool)
            else {
                throw FunctionCallResolutionError.toolNotVisible(tool)
            }

            return try (await currentTools()).invocation(
                for: functionCall
            )
        } catch {
            try await answer(functionCall, failingWith: error, checkpoint: &checkpoint)
            return nil
        }
    }

    /// Preflights an invocation under the execution policy. A failure is
    /// answered to the model and yields nil.
    private func review(
        _ invocation: ToolInvocation,
        for functionCall: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> ToolInvocation.Review? {
        do {
            return try await ToolExecutor(
                registry: (await currentTools()),
                policy: configuration.toolExecutionPolicy,
                recovery: configuration.recovery
            ).review(
                invocation,
                context: await makeToolContext()
            )
        } catch {
            try await answer(functionCall, failingWith: error, checkpoint: &checkpoint)
            return nil
        }
    }

    private func answer(
        _ functionCall: FunctionCall,
        failingWith error: Error,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        try await appendToolResult(
            try makeToolErrorResult(for: functionCall, error: error),
            for: functionCall,
            disposition: .failed_preflight,
            to: &checkpoint,
            summary: localizedDescription(for: error)
        )
        try await saveCheckpoint(&checkpoint)
    }

    /// Tools that pause the run for the operator instead of producing a result:
    /// clarifying questions and workspace access grants.
    private func interact(
        _ review: ToolInvocation.Review,
        for functionCall: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> CallOutcome? {
        let tool = ToolIdentifier(functionCall.name)

        if tool == Standard.Tools.ClarifyWithUser.identifier {
            suspendToolBatch(
                for: functionCall,
                disposition: .suspended_for_user_input,
                on: &checkpoint
            )
            return .stop(
                try await suspendForUserInput(
                    review.invocation,
                    checkpoint: &checkpoint
                )
            )
        }

        guard tool == SystemIO.Tools.RequestPathGrant.identifier else {
            return nil
        }

        if let stopped = try await interruptionBeforeToolExecution(checkpoint) {
            return .stop(stopped)
        }

        let execution = try await executeApprovedToolReview(review)
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
            try await saveCheckpoint(&checkpoint)
            return .next
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
        return .stop(
            try await suspendForWorkspaceAccess(
                request,
                functionCall: functionCall,
                checkpoint: &checkpoint
            )
        )
    }

    /// Runs an approved call and records its result.
    private func execute(
        _ review: ToolInvocation.Review,
        for functionCall: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> CallOutcome {
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
            return .stop(stopped)
        }

        let execution = try await executeApprovedToolReview(review)
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

        if let skipped = flow.remainder(afterExecuting: review.preflight) {
            try await appendSkippedSiblings(
                after: functionCall.id,
                to: &checkpoint,
                disposition: skipped,
                reason: siblingReason(for: skipped)
            )
            return .endBatch
        }

        try await saveCheckpoint(&checkpoint)
        return .next
    }

    /// Answers a denied call and applies the flow's rule for its siblings.
    private func reject(
        _ functionCall: FunctionCall,
        review: ToolInvocation.Review,
        disposition: AgentToolUseDisposition,
        summary: String,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> CallOutcome {
        try await appendToolResult(
            try makeDeniedToolResult(
                for: functionCall,
                preflight: review.preflight,
                requirement: review.requirement
            ),
            for: functionCall,
            disposition: disposition,
            to: &checkpoint,
            summary: summary
        )
        try await appendRunEvent(
            .init(
                kind: .tool_denied,
                iteration: checkpoint.state.iteration,
                callID: functionCall.id,
                toolName: functionCall.name,
                summary: summary
            ),
            to: &checkpoint
        )

        let skipped = flow.remainderAfterDenial
        try await appendSkippedSiblings(
            after: functionCall.id,
            to: &checkpoint,
            disposition: skipped,
            reason: siblingReason(for: skipped)
        )
        return .endBatch
    }
}
