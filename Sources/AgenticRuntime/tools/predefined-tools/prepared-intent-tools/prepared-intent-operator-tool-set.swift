import AgenticExecution

public struct PreparedIntentOperatorToolSet: AgentToolSet {
    public let manager: PreparedIntentManager
    public let executor: PreparedIntentExecutor?

    public init(
        manager: PreparedIntentManager,
        executor: PreparedIntentExecutor? = nil
    ) {
        self.manager = manager
        self.executor = executor
    }

    public func register(
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
