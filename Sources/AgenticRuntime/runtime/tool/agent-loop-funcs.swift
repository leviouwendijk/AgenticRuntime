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
        definitions: [ToolDescriptor],
        iteration: Int,
        sessionID: String
    ) async throws -> AgentRequest {
        let projected: [Message]
        if configuration.contextMode == .accumulating,
           let strategy = configuration.compactionStrategy {
            projected = AgentCompactor(strategy: strategy)
                .project(
                    messages: messages,
                    iteration: iteration,
                    sessionID: sessionID,
                    budget: contextBudget()
                )?.messages ?? messages
        } else {
            projected = messages
        }
        return AgentRequest(
            messages: projected,
            tools: definitions,
            generationConfiguration: request.generationConfiguration,
            responseFormat: request.responseFormat,
            invocationoptions: request.invocationoptions,
            metadata: request.metadata
        )
    }

    /// Budget of the route the broker would choose for this request. Routing is
    /// side-effect free here; unknown limits fall back to the trigger's own caps.
    func contextBudget() -> ContextBudget {
        guard let broker = model.invoker as? ModelBroker,
              let routed = try? broker.route(selection: model.selection)
        else {
            return .unknown
        }

        return .init(
            inputTokenLimit: routed.route.profile.limits.inputTokens
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

    func functionCalls(
        in message: Message
    ) -> [FunctionCall] {
        message.content.blocks.compactMap { block in
            guard case .call(let value) = block else {
                return nil
            }

            return value
        }
    }

    func appendToolResultBlock(
        _ block: MessageContentBlock,
        to state: inout AgentExecutor.State
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

    func executeApprovedCall(
        _ pendingApproval: PendingApproval,
        advertisedTools: [ToolIdentifier]?
    ) async throws -> ToolExecution.Result {
        let available = await capabilityState.available
        guard advertisedTools?.contains(ToolIdentifier(pendingApproval.functionCall.name)) == true,
              available.tools.contains(ToolIdentifier(pendingApproval.functionCall.name))
        else {
            throw FunctionCallResolutionError.toolNotVisible(
                ToolIdentifier(pendingApproval.functionCall.name)
            )
        }

        let invoker = ToolExecutor(
            registry: (await currentTools()),
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery
        )
        let invocation = try (await currentTools()).invocation(
            for: pendingApproval.functionCall
        )
        // The approved plan is the one captured by the checkpoint, not a
        // freshly generated preflight/plan with a different identity.
        let requirement = invoker.policy.evaluate(pendingApproval.preflight)
        guard requirement == pendingApproval.requirement else {
            throw RuntimeApprovedToolInvocationError.stale_preflight
        }
        let freshReview = ToolInvocation.Review(
            invocation: invocation,
            preflight: pendingApproval.preflight,
            requirement: pendingApproval.requirement,
            preparedOperation: pendingApproval.preparedOperation
        )

        return try await executeApprovedToolReview(
            freshReview
        )
    }

    func executeApprovedToolReview(
        _ review: ToolInvocation.Review
    ) async throws -> ToolExecution.Result {
        let available = await capabilityState.available
        guard available.tools.contains(review.invocation.tool) else {
            throw FunctionCallResolutionError.toolNotVisible(review.invocation.tool)
        }
        let invoker = ToolExecutor(
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
            inspections: await inventory.capabilityInspections(),
            services: tooling.services
        )
    }

    func makeDeniedToolResult(
        for functionCall: FunctionCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) throws -> FunctionCall.Response {
        let payload = ToolDenialPayload(
            kind: "tool_denied",
            callID: functionCall.id,
            toolName: functionCall.name,
            requirement: requirement.rawValue,
            summary: preflight.summary
        )

        return FunctionCall.Response(
            call: functionCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: true
        )
    }

    func makeSkippedToolResult(
        for functionCall: FunctionCall,
        summary: String = "Skipped explicitly by the operator."
    ) throws -> FunctionCall.Response {
        let payload = ToolSkipPayload(
            kind: "tool_skipped",
            callID: functionCall.id,
            toolName: functionCall.name,
            summary: summary
        )

        return FunctionCall.Response(
            call: functionCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: false
        )
    }

    func makeToolErrorResult(
        for functionCall: FunctionCall,
        error: Error
    ) throws -> FunctionCall.Response {
        let payload = ToolErrorPayload(
            kind: "tool_error",
            callID: functionCall.id,
            toolName: functionCall.name,
            message: localizedDescription(for: error)
        )

        return FunctionCall.Response(
            call: functionCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: true
        )
    }

    func suspendedResult(
        from checkpoint: AgentExecutor.Checkpoint
    ) throws -> AgentExecutor.Result {
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
            costRecord: checkpoint.costRecord,
                invocations: checkpoint.invocations
        )
    }

    func suspendForUserInput(
        _ invocation: ToolInvocation,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> ToolProcessingOutcome {
        let input = try JSONCoding.default.decode(
            Standard.Tools.ClarifyWithUser.Input.self,
            from: invocation.arguments
        )
        let request = try input.request()
        let suspension = Run.Suspension.user_input(
            request,
            metadata: [
                "callID": invocation.id,
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
                callID: invocation.id,
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
        functionCall: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> ToolProcessingOutcome {
        let suspension = Run.Suspension.workspace_access(
            request,
            metadata: [
                "callID": functionCall.id,
                "toolName": functionCall.name
            ]
        )

        checkpoint.suspend(
            suspension
        )

        try await appendRunEvent(
            .init(
                kind: .pending_workspace_access,
                iteration: checkpoint.state.iteration,
                callID: functionCall.id,
                toolName: functionCall.name,
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
        _ checkpoint: inout AgentExecutor.Checkpoint
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
            checkpoint: checkpoint,
            budget: contextBudget()
        ) else {
            return
        }

        let event = Run.Event.State(
            kind: .compaction,
            iteration: checkpoint.state.iteration,
            messageID: compacted.summaryMessageID,
            summary: "projected \(compacted.replacedMessageCount) earlier message(s) for inference"
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
        _ checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let root_id = AgentExecutionInvocation.root_id(session_id: checkpoint.id)
        if let index = checkpoint.invocations.firstIndex(where: { $0.id == root_id }) {
            let phase_state: AgentExecutionInvocation.State
            switch checkpoint.phase {
            case .completed: phase_state = .completed
            case .failed: phase_state = .failed
            case .interrupted: phase_state = .interrupted
            case .suspended, .awaiting_approval: phase_state = .suspended
            case .ready_for_model, .receiving_model_response, .processing_tool_calls:
                phase_state = .running
            }
            if checkpoint.invocations[index].state != phase_state {
                checkpoint.invocations[index].transition(to: phase_state)
            }
        }
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
        _ checkpoint: AgentExecutor.Checkpoint
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
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        try observe_invocation_event(event, in: &checkpoint)
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

    func recordFunctionCall(
        _ functionCall: FunctionCall
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordFunctionCall(
                functionCall
            )
        }
    }

    func recordToolResult(
        _ result: FunctionCall.Response
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
