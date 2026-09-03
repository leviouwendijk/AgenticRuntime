import Agentic
import AgenticExecution

extension ToolLoopExecutor {
    func modelInvocationContext(
        sessionID: String,
        journal: AgentModelToolInvocationJournal
    ) -> AgentModelInvocationContext {
        let governed = GovernedAgentToolCallResolver(
            registry: toolRegistry,
            exposure: toolExposure,
            policy: configuration.toolExecutionPolicy,
            context: AgentToolExecutionContext(
                workspace: workspace,
                sessionID: sessionID,
                executionMode: .model_tool_call
            ),
            approvalHandler: approvalHandler,
            resolutionObserver: { invocation in
                await journal.append(
                    invocation
                )
            }
        )

        return AgentModelInvocationContext(
            toolCallResolver: RuntimeAgentToolCallResolver(
                resolver: governed,
                registry: toolRegistry,
                exposure: toolExposure
            )
        )
    }
}
