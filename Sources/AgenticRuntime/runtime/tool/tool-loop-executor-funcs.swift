import Agentic
import AgenticExecution
import AgenticIO
import AgenticStandard
import Workspace
import Foundation
import Primitives

extension ToolLoopExecutor {
    func requestWithCurrentState(
        from request: AgentRequest,
        messages: [Message]
    ) async throws -> AgentRequest {
        let definitions = try await toolDefinitions(
            fallback: request.tools
        )

        return AgentRequest(
            messages: messages,
            tools: definitions,
            generationConfiguration: request.generationConfiguration,
            responseFormat: request.responseFormat,
            invocationoptions: request.invocationoptions,
            metadata: request.metadata
        )
    }

    func toolDefinitions(
        fallback: [ToolDescriptor]
    ) async throws -> [ToolDescriptor] {
        guard !tooling.registry.isEmpty else {
            return fallback
        }

        return try await toolExposure.definitions(
            in: tooling.registry
        )
    }

    func toolCalls(
        in message: Message
    ) -> [ToolCall] {
        message.content.blocks.compactMap { block in
            guard case .tool_call(let value) = block else {
                return nil
            }

            return value
        }
    }

    func appendToolResultBlock(
        _ block: MessageContentBlock,
        to state: inout AgentLoopState
    ) {
        if configuration.appendToolResultsAsMessages {
            state.messages.append(
                Message(
                    role: .tool,
                    content: .init(
                        blocks: [block]
                    )
                )
            )
            return
        }

        if let last = state.messages.last,
           last.role == .tool {
            var updated = last
            updated.content.blocks.append(
                block
            )
            state.messages.removeLast()
            state.messages.append(
                updated
            )
            return
        }

        state.messages.append(
            Message(
                role: .tool,
                content: .init(
                    blocks: [block]
                )
            )
        )
    }

    func resolveApprovalDecision(
        for preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) async throws -> ApprovalDecision {
        guard let approvalHandler = tooling.approvalHandler else {
            return requirement.decision
        }

        return try await approvalHandler.decide(
            on: preflight,
            requirement: requirement
        )
    }

    func executeApprovedToolCall(
        _ toolCall: ToolCall,
        preflight: ToolPreflight
    ) async throws -> ToolExecutionResult {
        try await executeApprovedToolReview(
            ToolInvocation.Review(
                call: toolCall,
                preflight: preflight,
                requirement: configuration
                    .toolExecutionPolicy
                    .evaluate(preflight)
            )
        )
    }

    func executeApprovedToolCall(
        _ pendingApproval: PendingApproval
    ) async throws -> ToolExecutionResult {
        let invoker = ToolInvoker(
            registry: tooling.registry,
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery
        )
        let freshReview = try await invoker.review(
            pendingApproval.toolCall,
            workspace: tooling.workspace
        )

        guard freshReview.preflight == pendingApproval.preflight,
              freshReview.requirement == pendingApproval.requirement
        else {
            throw RuntimeApprovedToolInvocationError.stale_preflight
        }

        return try await executeApprovedToolReview(
            freshReview
        )
    }

    func executeApprovedToolReview(
        _ review: ToolInvocation.Review
    ) async throws -> ToolExecutionResult {
        let invoker = ToolInvoker(
            registry: tooling.registry,
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery
        )
        let invocation = try await invoker.invoke(
            review,
            workspace: tooling.workspace,
            approvalHandler: RuntimeResolvedToolApprovalHandler(
                decision: .approved
            )
        )

        guard case .executed(let execution) = invocation.outcome else {
            throw RuntimeApprovedToolInvocationError.not_executed
        }

        return execution
    }
    func makeDeniedToolResult(
        for toolCall: ToolCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) throws -> ToolResult {
        let payload = ToolDenialPayload(
            kind: "tool_denied",
            toolCallID: toolCall.id,
            toolName: toolCall.tool.rawValue,
            requirement: requirement.rawValue,
            summary: preflight.summary
        )

        return ToolResult(
            toolCallID: toolCall.id,
            tool: toolCall.tool,
            output: try JSONToolBridge.encode(payload),
            isError: true
        )
    }

    func makeSkippedToolResult(
        for toolCall: ToolCall,
        summary: String = "Skipped explicitly by the operator."
    ) throws -> ToolResult {
        let payload = ToolSkipPayload(
            kind: "tool_skipped",
            toolCallID: toolCall.id,
            toolName: toolCall.tool.rawValue,
            summary: summary
        )

        return ToolResult(
            toolCallID: toolCall.id,
            tool: toolCall.tool,
            output: try JSONToolBridge.encode(payload),
            isError: false
        )
    }

    func makeToolErrorResult(
        for toolCall: ToolCall,
        error: Error
    ) throws -> ToolResult {
        let payload = ToolErrorPayload(
            kind: "tool_error",
            toolCallID: toolCall.id,
            toolName: toolCall.tool.rawValue,
            message: localizedDescription(for: error)
        )

        return ToolResult(
            toolCallID: toolCall.id,
            tool: toolCall.tool,
            output: try JSONToolBridge.encode(payload),
            isError: true
        )
    }

    func suspendedResult(
        from checkpoint: AgentHistoryCheckpoint
    ) throws -> AgentRunResult {
        guard let response = checkpoint.lastResponse else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without last response"
            )
        }

        guard let suspension = checkpoint.resolvedSuspension else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without suspension payload"
            )
        }

        return .suspended(
            sessionID: checkpoint.id,
            response: response,
            suspension: suspension,
            state: checkpoint.state,
            events: checkpoint.events,
            toolUses: checkpoint.resolvedToolUses,
            costRecord: checkpoint.costRecord
        )
    }

    func suspendForUserInput(
        _ toolCall: ToolCall,
        checkpoint: inout AgentHistoryCheckpoint
    ) async throws -> ToolProcessingOutcome {
        let input = try JSONToolBridge.decode(
            Standard.Tools.ClarifyWithUser.Input.self,
            from: toolCall.input
        )
        let request = try input.request()
        let suspension = AgentSuspension.user_input(
            request,
            metadata: [
                "toolCallID": toolCall.id,
                "toolName": toolCall.tool.rawValue
            ]
        )

        checkpoint.suspend(
            suspension
        )

        try await appendRunEvent(
            .init(
                kind: .pending_user_input,
                iteration: checkpoint.state.iteration,
                toolCallID: toolCall.id,
                toolName: toolCall.tool.rawValue,
                summary: request.prompt
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

    func suspendForWorkspaceAccess(
        _ request: WorkspaceAccessRequest,
        toolCall: ToolCall,
        checkpoint: inout AgentHistoryCheckpoint
    ) async throws -> ToolProcessingOutcome {
        let suspension = AgentSuspension.workspace_access(
            request,
            metadata: [
                "toolCallID": toolCall.id,
                "toolName": toolCall.tool.rawValue
            ]
        )

        checkpoint.suspend(
            suspension
        )

        try await appendRunEvent(
            .init(
                kind: .pending_workspace_access,
                iteration: checkpoint.state.iteration,
                toolCallID: toolCall.id,
                toolName: toolCall.tool.rawValue,
                summary: "workspace access resolution required"
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

    func localizedDescription(
        for error: Error
    ) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(
            describing: error
        )
    }

    func compactIfNeeded(
        _ checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        guard let strategy = configuration.compactionStrategy else {
            return
        }

        guard checkpoint.phase == .ready_for_model else {
            return
        }

        let compactor = AgentCompactor(
            strategy: strategy
        )

        guard let compacted = compactor.compact(
            checkpoint: &checkpoint
        ) else {
            return
        }

        let event = AgentRunEvent(
            kind: .compaction,
            iteration: checkpoint.state.iteration,
            messageID: compacted.summaryMessageID,
            summary: "compacted \(compacted.replacedMessageCount) earlier message(s)"
        )

        try await appendRunEvent(
            event,
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )
    }

    func saveCheckpoint(
        _ checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        checkpoint.exposedToolIdentifiers = try await toolExposure.identifiers(
            in: tooling.registry
        )
        checkpoint.touch()

        await publishRunState(
            checkpoint
        )

        guard configuration.persistsHistory else {
            return
        }

        guard let historyStore = recording.historyStore else {
            return
        }

        try await historyStore.saveCheckpoint(
            checkpoint
        )
    }

    func publishRunState(
        _ checkpoint: AgentHistoryCheckpoint
    ) async {
        guard !recording.stateSinks.isEmpty else {
            return
        }

        let snapshot = AgentRunStateSnapshot(
            checkpoint: checkpoint
        )

        for sink in recording.stateSinks {
            await sink.publish(
                snapshot
            )
        }
    }

    func appendRunEvent(
        _ event: AgentRunEvent,
        to checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        checkpoint.events.append(
            event
        )

        try await recordRunEvent(
            event
        )
    }

    func recordMessage(
        _ message: Message
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordMessage(
                message
            )
        }
    }

    func recordMessages(
        _ messages: [Message]
    ) async throws {
        for message in messages {
            try await recordMessage(
                message
            )
        }
    }

    func recordToolCall(
        _ toolCall: ToolCall
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordToolCall(
                toolCall
            )
        }
    }

    func recordToolResult(
        _ result: ToolResult
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordToolResult(
                result
            )
        }
    }

    func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordRunEvent(
                event
            )
        }
    }
}

private enum RuntimeApprovedToolInvocationError: Error, Sendable {
    case stale_preflight
    case not_executed
}

private struct RuntimeResolvedToolApprovalHandler:
    ToolApprovalHandler,
    Sendable
{
    let decision: ApprovalDecision

    func decide(
        on _: ToolPreflight,
        requirement _: ApprovalRequirement
    ) async throws -> ApprovalDecision {
        decision
    }
}
