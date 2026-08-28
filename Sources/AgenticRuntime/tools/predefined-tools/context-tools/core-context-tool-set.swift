import AgenticExecution

public struct CoreContextToolSet: AgentToolSet {
    public let composer: ContextComposer

    public init(
        composer: ContextComposer = .init()
    ) {
        self.composer = composer
    }

    public func register(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            ComposeContextTool(
                composer: composer
            )

            InspectContextSourcesTool()

            EstimateContextSizeTool(
                composer: composer
            )
        }
    }
}
