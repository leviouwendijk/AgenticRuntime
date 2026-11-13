import Agentic

/// Extensions may prepare messages or sampling settings, but cannot smuggle
/// changed function declarations or reorder bindings into the provider request.
enum RuntimeModelToolAuthorizationError: Error, Sendable {
    case invalidProjection
    case invalidArguments
}

extension AgentLoop {
    func modelInvocationContext(
        request: AgentRequest,
        projection: ModelCapabilityProjection,
        advertisedTools: [ToolDescriptor],
        sessionID: String,
        journal: AgentModelToolInvocationJournal
    ) async throws -> AgentModelInvocationContext {
        // Validate extensions against the exact function declarations bound
        // to this turn, not a newly acquired visibility snapshot.
        guard request.tools == advertisedTools,
              request.tools.map(\.name) == projection.functions.map(\.name)
        else {
            throw RuntimeModelToolAuthorizationError.invalidProjection
        }
        return AgentModelInvocationContext(
            functionCallResolver: CapabilityFunctionCallResolver(
                dispatcher: await modelDispatcher(sessionID: sessionID, journal: journal),
                projection: projection,
                journal: journal
            )
        )
    }
}
