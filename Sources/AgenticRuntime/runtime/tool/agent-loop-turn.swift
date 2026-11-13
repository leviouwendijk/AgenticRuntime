import Agentic
import Foundation

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
