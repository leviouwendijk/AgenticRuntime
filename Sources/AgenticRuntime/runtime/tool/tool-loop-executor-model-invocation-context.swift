import Agentic
import AgenticExecution

extension ToolLoopExecutor {
    func modelInvocationContext(
        sessionID: String
    ) -> AgentModelInvocationContext {
        AgentModelInvocationContext(
            toolCallResolver: GovernedAgentToolCallResolver(
                registry: toolRegistry,
                exposure: toolExposure,
                policy: configuration.toolExecutionPolicy,
                context: AgentToolExecutionContext(
                    workspace: workspace,
                    sessionID: sessionID,
                    executionMode: .model_tool_call
                ),
                approvalHandler: approvalHandler
            )
        )
    }
}
