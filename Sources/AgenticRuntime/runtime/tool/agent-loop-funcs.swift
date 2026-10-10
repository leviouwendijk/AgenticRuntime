import Agentic
import AgenticIO
import AgenticStandard
import Workspace
import Foundation
import Primitives

extension AgentLoop {
    func requestWithCurrentState(
        from request: AgentRequest,
        messages: [Message],
        definitions: [ToolDescriptor]
    ) async throws -> AgentRequest {

        return AgentRequest(
            messages: messages,
            tools: definitions,
            generationConfiguration: request.generationConfiguration,
            responseFormat: request.responseFormat,
            invocationoptions: request.invocationoptions,
            metadata: request.metadata
        )
    }

    /// Existing providers accept ToolDescriptor as their function transport.
    /// Semantic Program/Inference identifiers are never executed as Tools:
    /// dispatch uses the request-bound ModelCapabilityProjection instead.
    func modelCapabilityDefinitions(
        for projection: ModelCapabilityProjection
    ) async throws -> [ToolDescriptor] {
        let toolIDs = projection.entries.compactMap { entry -> ToolIdentifier? in
            if case .tool(let identifier) = entry.target {
                return identifier
            }
            return nil
        }
        let tools = await inventory.tools()
        let actualTools = try tools.modelFacingDefinitions(for: toolIDs)
        let toolsByName = Dictionary(
            uniqueKeysWithValues: actualTools.map { ($0.name, $0) }
        )
        return try projection.entries.map { entry in
            if case .tool = entry.target {
                guard let tool = toolsByName[entry.function.name],
                      tool.modelFunction == entry.function else {
                    throw RuntimeModelToolAuthorizationError.invalidProjection
                }
                return tool
            }
            return ToolDescriptor(
                name: entry.function.name,
                description: entry.function.description,
                input: entry.function.input
            )
        }
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
        to state: inout AgentRunner.State
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
        _ pendingApproval: PendingApproval,
        advertisedTools: [ToolIdentifier]?
    ) async throws -> ToolExecution.Result {
        let available = await capabilityState.available
        guard advertisedTools?.contains(pendingApproval.toolCall.tool) == true,
              available.tools.contains(pendingApproval.toolCall.tool)
        else {
            throw AgentToolCallResolutionError.toolNotVisible(
                pendingApproval.toolCall.tool
            )
        }

        let invoker = ToolInvoker(
            registry: (await currentTools()),
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery
        )
        let invocation = try (await currentTools()).invocation(
            for: pendingApproval.toolCall
        )
        let freshReview = try await invoker.review(
            invocation,
            context: await makeToolContext()
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
    ) async throws -> ToolExecution.Result {
        let available = await capabilityState.available
        guard available.tools.contains(review.invocation.tool) else {
            throw AgentToolCallResolutionError.toolNotVisible(review.invocation.tool)
        }
        let invoker = ToolInvoker(
            registry: (await currentTools()),
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery,
            observationHandler: { observation in
                try? await self.record(
                    .tool_observation(observation)
                )
            }
        )
        let invocation = try await invoker.invoke(
            review,
            context: await makeToolContext(),
            approvalHandler: RuntimeResolvedToolApprovalHandler(
                decision: .approved
            )
        )

        guard case .executed(let execution) = invocation.outcome else {
            throw RuntimeApprovedToolInvocationError.not_executed
        }

        return execution
    }

    func makeToolContext() async -> ToolContext {
        ToolContext(
            workspace: tooling.workspace,
            catalog: await inventory.catalog(),
            capabilities: capabilityState,
            inspections: await inventory.capabilityInspections()
        )
    }

    func makeDeniedToolResult(
        for toolCall: ToolCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) throws -> ToolCall.Response {
        let payload = ToolDenialPayload(
            kind: "tool_denied",
            toolCallID: toolCall.id,
            toolName: toolCall.tool.rawValue,
            requirement: requirement.rawValue,
            summary: preflight.summary
        )

        return ToolCall.Response(
            call: toolCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: true
        )
    }

    func makeSkippedToolResult(
        for toolCall: ToolCall,
        summary: String = "Skipped explicitly by the operator."
    ) throws -> ToolCall.Response {
        let payload = ToolSkipPayload(
            kind: "tool_skipped",
            toolCallID: toolCall.id,
            toolName: toolCall.tool.rawValue,
            summary: summary
        )

        return ToolCall.Response(
            call: toolCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: false
        )
    }

    func makeToolErrorResult(
        for toolCall: ToolCall,
        error: Error
    ) throws -> ToolCall.Response {
        let payload = ToolErrorPayload(
            kind: "tool_error",
            toolCallID: toolCall.id,
            toolName: toolCall.tool.rawValue,
            message: localizedDescription(for: error)
        )

        return ToolCall.Response(
            call: toolCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: true
        )
    }

    func suspendedResult(
        from checkpoint: AgentRunner.Checkpoint
    ) throws -> AgentRunner.Result {
        guard let suspension = checkpoint.resolvedSuspension else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without suspension payload"
            )
        }

        return .suspended(
            sessionID: checkpoint.id,
            phase: checkpoint.phase,
            response: checkpoint.lastResponse,
            suspension: suspension,
            state: checkpoint.state,
            events: checkpoint.events,
            toolUses: checkpoint.resolvedToolUses,
            costRecord: checkpoint.costRecord
        )
    }

    func suspendForUserInput(
        _ invocation: ToolInvocation,
        checkpoint: inout AgentRunner.Checkpoint
    ) async throws -> ToolProcessingOutcome {
        let input = try JSONCoding.default.decode(
            Standard.Tools.ClarifyWithUser.Input.self,
            from: invocation.arguments
        )
        let request = try input.request()
        let suspension = Run.Suspension.user_input(
            request,
            metadata: [
                "toolCallID": invocation.id,
                "toolName": invocation.tool.rawValue
            ]
        )

        checkpoint.suspend(
            suspension
        )

        try await appendRunEvent(
            .init(
                kind: .pending_user_input,
                iteration: checkpoint.state.iteration,
                toolCallID: invocation.id,
                toolName: invocation.tool.rawValue,
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
        checkpoint: inout AgentRunner.Checkpoint
    ) async throws -> ToolProcessingOutcome {
        let suspension = Run.Suspension.workspace_access(
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
        _ checkpoint: inout AgentRunner.Checkpoint
    ) async throws {
        guard configuration.contextMode == .accumulating,
              let strategy = configuration.compactionStrategy else {
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

        let event = Run.Event.State(
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
        _ checkpoint: inout AgentRunner.Checkpoint
    ) async throws {
        checkpoint.capabilities =
            await capabilityState.snapshot()
        if configuration.contextMode == .dynamic, let contextAllocator {
            checkpoint.contextWorkingSet = try await contextAllocator.snapshot(checkpoint.id)
            checkpoint.contextTransitions = await contextAllocator.recordedOperations(for: checkpoint.id)
        }
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
        _ checkpoint: AgentRunner.Checkpoint
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
        _ event: Run.Event.State,
        to checkpoint: inout AgentRunner.Checkpoint
    ) async throws {
        checkpoint.events.append(
            event
        )

        try await record(
            .state(event)
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
        _ result: ToolCall.Response
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordToolResult(
                result
            )
        }
    }

    func record(
        _ event: Run.Event
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.record(
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
