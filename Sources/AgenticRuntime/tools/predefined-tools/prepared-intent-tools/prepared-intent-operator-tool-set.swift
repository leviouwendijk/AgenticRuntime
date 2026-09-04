import AgenticExecution

public struct PreparedIntentOperatorToolSet: AgentToolSet {
    public let manager: PreparedIntentManager
    public let executionRegistry: ToolRegistry?
    public let sessionID: String?

    public init(
        manager: PreparedIntentManager,
        executionRegistry: ToolRegistry? = nil,
        sessionID: String? = nil
    ) {
        self.manager = manager
        self.executionRegistry = executionRegistry
        self.sessionID = sessionID
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

            if let executionRegistry {
                ExecutePreparedIntentTool(
                    manager: manager,
                    registry: executionRegistry,
                    sessionID: sessionID
                )
            }
        }
    }
}
