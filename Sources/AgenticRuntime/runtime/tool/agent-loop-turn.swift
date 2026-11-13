import Agentic
import AgenticIO
import AgenticStandard
import Foundation
import Primitives
import Workspace

extension AgentLoop {
    /// What one model turn sends: the capability view it advertises and the
    /// prepared request, with its measured input composition.
    struct Turn {
        let projection: ModelCapabilityProjection
        let tools: [ToolDescriptor]
        let request: AgentRequest
        let usage: Context.Usage
    }

    /// Builds the request for the next model turn. Compaction, dynamic context
    /// allocation and harness extensions all happen here, so every transport
    /// sends the same frame.
    func prepareTurn(
        _ checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> Turn {
        try await compactIfNeeded(
            &checkpoint
        )

        // Snapshot the request's capabilities once. Request preparation,
        // advertised transport, and invocation authorization share that view.
        let projection = try await inventory.modelProjection()
        let tools = try await modelCapabilityDefinitions(
            for: projection
        )
        let request = try await prepareModelRequest(
            from: try await requestWithCurrentState(
                from: checkpoint.originalRequest,
                messages: checkpoint.state.messages,
                definitions: tools,
                iteration: checkpoint.state.iteration,
                sessionID: checkpoint.id
            ),
            checkpoint: checkpoint
        )
        let usage = Context.Usage(
            turn: checkpoint.state.iteration + 1,
            request: request
        )

        checkpoint.lastAdvertisedCapabilities = projection
        checkpoint.lastAdvertisedTools = projection.entries.compactMap { entry in
            if case .tool(let identifier) = entry.target {
                return identifier
            }
            return nil
        }
        checkpoint.contextUsage.append(usage)

        try await appendRunEvent(
            .init(
                kind: .context_usage,
                iteration: checkpoint.state.iteration,
                summary: usage.summary
            ),
            to: &checkpoint
        )

        return Turn(
            projection: projection,
            tools: tools,
            request: request,
            usage: usage
        )
    }
}

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
}
