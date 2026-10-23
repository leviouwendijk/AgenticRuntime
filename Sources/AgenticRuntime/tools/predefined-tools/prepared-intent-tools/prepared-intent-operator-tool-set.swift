// FROZEN: deferred queue (not conversational or ToolPlan execution).
#if AGENTIC_ENABLE_DEFERRED_INTENTS
import Agentic

public struct PreparedIntentOperatorToolSet: AgentToolProvider {
    public let manager: PreparedIntentManager
    public let executor: PreparedIntentExecutor?

    public init(
        manager: PreparedIntentManager,
        executor: PreparedIntentExecutor? = nil
    ) {
        self.manager = manager
        self.executor = executor
    }

    public func registerTools(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            ListPreparedIntentsTool(
                manager: manager
            )
            ReadPreparedIntentTool(
                manager: manager
            )
            ReviewPreparedIntentTool(
                manager: manager
            )

            if let executor {
                ExecutePreparedIntentTool(
                    executor: executor
                )
            }
        }
    }
}

#endif // AGENTIC_ENABLE_DEFERRED_INTENTS