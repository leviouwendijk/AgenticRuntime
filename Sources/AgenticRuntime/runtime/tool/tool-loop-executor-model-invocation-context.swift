import Agentic

extension ToolLoopExecutor {
    func modelInvocationContext(
        sessionID: String,
        journal: AgentModelToolInvocationJournal
    ) async -> AgentModelInvocationContext {
        let visible =
            await capabilityState.visible
        let governed = GovernedAgentToolCallResolver(
            registry: tooling.registry,
            visibleToolIdentifiers: visible.tools,
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery,
            context: makeToolContext(),
            approvalHandler: tooling.approvalHandler,
            resolutionObserver: { invocation in
                await journal.append(
                    invocation
                )
            }
        )

        return AgentModelInvocationContext(
            toolCallResolver: RuntimeToolCallResolver(
                resolver: governed,
                capabilityState: capabilityState
            )
        )
    }
}
