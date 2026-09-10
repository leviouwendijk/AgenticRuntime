import Agentic
import AgenticExecution

extension ToolLoopExecutor {
    func modelInvocationContext(
        sessionID: String,
        journal: AgentModelToolInvocationJournal
    ) -> AgentModelInvocationContext {
        let governed = GovernedAgentToolCallResolver(
            registry: tooling.registry,
            exposure: toolExposure,
            policy: configuration.toolExecutionPolicy,
            context: AgentToolExecutionContext(
                workspace: tooling.workspace,
                sessionID: sessionID,
                executionMode: .model_tool_call
            ),
            approvalHandler: tooling.approvalHandler,
            resolutionObserver: { invocation in
                await journal.append(
                    invocation
                )
            }
        )

        return AgentModelInvocationContext(
            toolCallResolver: RuntimeAgentToolCallResolver(
                resolver: governed,
                registry: tooling.registry,
                exposure: toolExposure
            )
        )
    }
}
