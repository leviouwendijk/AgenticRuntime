import Agentic

extension ToolLoopExecutor {
    func modelInvocationContext(
        sessionID: String,
        journal: AgentModelToolInvocationJournal
    ) -> AgentModelInvocationContext {
        let governed = GovernedAgentToolCallResolver(
            registry: tooling.registry,
            exposure: visibility,
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery,
            workspace: tooling.workspace,
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
                registry: tooling.registry,
                exposure: visibility
            )
        )
    }
}
