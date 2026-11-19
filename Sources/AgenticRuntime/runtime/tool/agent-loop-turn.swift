import Agentic
import AgenticContextWindow
import AgenticHarness
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
        let usage: ContextWindow.Usage
        /// The lexical estimate of the prepared request, in dynamic mode.
        let estimatedInputTokens: Int?
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

        // The opening: grants are applied once, before the first request,
        // so the advertised tools stay fixed unless the model reveals more.
        let before = await capabilityState.snapshot()
        let granted = checkpoint.reportedCapabilities == nil
            ? await applyGrants()
            : []
        try await recordCapabilityChanges(before: before, granted: granted, to: &checkpoint)
        // Core schemas need the inspector in view; without it, full ones.
        let (schemas, reason) = await schemaDetail()

        // Snapshot the request's capabilities once. Request preparation,
        // advertised transport, and invocation authorization share that view.
        let projection = advertisingOrder(
            try await inventory.modelProjection(),
            after: checkpoint.events.last { $0.kind == .schemas_advertised }?.advertisement
        )
        let full = try await modelCapabilityDefinitions(for: projection)
        let tools = full.map { tool in
            schemas == .core && tool.identifier != Self.inspector ? tool.core : tool
        }
        try await recordAdvertisement(tools, full: full, detail: schemas, reason: reason, to: &checkpoint)
        let (request, preparation) = try await prepareModelRequest(
            from: try await requestWithCurrentState(
                from: checkpoint.request,
                messages: checkpoint.state.messages,
                definitions: tools,
                iteration: checkpoint.state.iteration,
                sessionID: checkpoint.id
            ),
            checkpoint: checkpoint
        )
        let usage = ContextWindow.Usage(
            turn: checkpoint.state.iteration + 1,
            request: request
        )
        try await recordContextChanges(preparation?.history, to: &checkpoint)
        try await recordContextPressure(preparation?.pressure, to: &checkpoint)

        checkpoint.lastAdvertisedCapabilities = projection
        checkpoint.lastAdvertisedTools = projection.entries.compactMap { entry in
            if case .tool(let identifier) = entry.target {
                return identifier
            }
            return nil
        }

        try await appendRunEvent(
            .init(
                kind: .context_usage,
                iteration: checkpoint.state.iteration,
                summary: usage.summary
            ),
            to: &checkpoint
        )
        try await record(
            .request(.init(request: request, usage: usage))
        )

        return Turn(
            projection: projection,
            tools: tools,
            request: request,
            usage: usage,
            estimatedInputTokens: preparation?.measurement.estimatedInputTokens
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

    static let inspector = Standard.Tools.InspectCapability.identifier

    /// What each grant adds in this run, or nil when its condition does
    /// not hold. Installation bounds it in `applyGrants`.
    func capabilities(
        of grant: AgentCapabilityGrant
    ) -> AgentCapabilitySet? {
        switch grant {
        case .ambient:
            return .ambient
        case .discovery:
            return .init(tools: Standard.Tools.discovery)
        case .session_readers:
            guard configuration.contextMode == .dynamic else { return nil }
            return .init(tools: ContextWindow.Compactor.requiredTools)
        case .result_reader:
            guard configuration.contextPolicy.resultBudget != nil,
                  (try? tooling.services.require(Run.Log.self)) != nil
            else { return nil }
            return .init(tools: [Standard.Tools.ReadResult.identifier])
        case .friction_notes:
            return .init(tools: [Harness.Tools.NoteFriction.identifier])
        }
    }

    /// Enables and exposes each grant the configuration takes, bounded by
    /// what the run installs, whatever the Agent declares. Returns each
    /// grant with what it covers, for attribution.
    func applyGrants() async -> [(AgentCapabilityGrant, AgentCapabilitySet)] {
        let installed = await capabilityState.snapshot().installed
        var applied: [(AgentCapabilityGrant, AgentCapabilitySet)] = []
        for grant in configuration.grants.granted {
            guard let capabilities = capabilities(of: grant)?.intersecting(installed),
                  capabilities != .none
            else { continue }
            _ = try? await capabilityState.enable(capabilities)
            _ = try? await capabilityState.expose(capabilities)
            applied.append((grant, capabilities))
        }
        return applied
    }

    /// The schema detail to advertise, and why. Core schemas are only safe
    /// while the inspector (the `discovery` grant) can return the rest;
    /// without it, full ones.
    func schemaDetail() async -> (ContextWindow.SchemaDetail, Run.Event.Advertisement.Reason) {
        guard configuration.contextPolicy.schemas == .core else {
            return (.full, .policy_full)
        }
        return await capabilityState.snapshot().visible.tools.contains(Self.inspector)
            ? (.core, .core)
            : (.full, .inspector_unavailable)
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

extension AgentLoop {
    /// Reports what this request's history selection decided that the run
    /// has not reported yet, so nothing leaves the model's view unseen by
    /// the operator, and a decision held across requests is reported once.
    func recordContextChanges(
        _ history: ContextWindow.HistorySelection?,
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        guard let changes = history?.changes, !changes.isEmpty else { return }
        let reported = Set(checkpoint.events.flatMap { state -> [ContextWindow.HistorySelection.Change] in
            state.kind == .context_changed ? state.contextChanges ?? [] : []
        })
        let new = changes.filter { !reported.contains($0) }
        guard !new.isEmpty else { return }
        let counts = Dictionary(grouping: new, by: { $0.reason }).map { reason, items in
            "\(items.count) \(reason.rawValue)"
        }.sorted()
        try await appendRunEvent(
            .init(
                kind: .context_changed,
                iteration: checkpoint.state.iteration,
                summary: counts.joined(separator: ", "),
                contextChanges: new
            ),
            to: &checkpoint
        )
    }
}

extension AgentLoop {
    /// Past the soft limit, once per run: how full the request is and what
    /// an explicit compaction would save. Advice only; nothing changes.
    func recordContextPressure(
        _ pressure: ContextWindow.Pressure?,
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        guard let pressure, pressure.level == .soft,
              !checkpoint.events.contains(where: { $0.kind == .context_pressure })
        else { return }
        let saving = await compactableTokens(in: checkpoint)
        try await appendRunEvent(
            .init(
                kind: .context_pressure,
                iteration: checkpoint.state.iteration,
                summary: "≈\(pressure.estimatedInputTokens) of \(pressure.hardLimit) input tokens "
                    + "(soft limit \(pressure.softLimit))"
                    + (saving > 0 ? "; :compact would save ≈\(saving), at the cost of one cache miss" : "")
            ),
            to: &checkpoint
        )
    }

    /// What compacting now would take out of later requests.
    func compactableTokens(
        in checkpoint: AgentExecutor.Checkpoint
    ) async -> Int {
        let done = await contextServices?.compactions?.compactions ?? []
        return ContextWindow.Compactor.plan(
            messages: checkpoint.state.messages,
            excluding: done
        )?.estimatedTokensSaved ?? 0
    }
}
