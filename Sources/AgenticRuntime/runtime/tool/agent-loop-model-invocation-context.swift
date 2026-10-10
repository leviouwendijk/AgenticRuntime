import Agentic

/// A model request must not smuggle duplicate or altered Tool schemas into
/// the direct function interface through a harness extension.
enum RuntimeModelToolAuthorizationError: Error, Sendable {
    case invalidProjection
}

extension AgentLoop {
    func modelInvocationContext(
        request: AgentRequest,
        sessionID: String,
        journal: AgentModelToolInvocationJournal
    ) async throws -> AgentModelInvocationContext {
        let visible = await capabilityState.visible
        let registry = await currentTools()
        let advertised = request.tools.map(\.identifier)
        guard Set(advertised).count == advertised.count else {
            throw RuntimeModelToolAuthorizationError.invalidProjection
        }
        for definition in request.tools {
            guard visible.tools.contains(definition.identifier),
                  registry.modelFacingDefinition(
                    identifiedBy: definition.identifier
                  ) == definition
            else {
                throw AgentToolCallResolutionError.toolNotVisible(
                    definition.identifier
                )
            }
        }
        let governed = GovernedAgentToolCallResolver(
            registry: registry,
            visibleToolIdentifiers: advertised,
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery,
            context: await makeToolContext(),
            approvalHandler: tooling.approvalHandler,
            observationHandler: { observation in
                try? await self.record(
                    .tool_observation(observation)
                )
            },
            resolutionObserver: { invocation in
                await journal.append(
                    invocation
                )
            }
        )

        return AgentModelInvocationContext(
            toolCallResolver: RuntimeToolCallResolver(
                resolver: governed,
                capabilityState: capabilityState,
                advertisedTools: Set(advertised)
            )
        )
    }
}
