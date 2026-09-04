import Agentic
import AgenticExecution

public typealias OperatorSessionCatalogToolSet = SessionCatalogToolSet

public struct SessionCatalogToolSet: AgentToolSet {
    public let catalog: AgentSessionCatalog

    public init(
        catalog: AgentSessionCatalog
    ) {
        self.catalog = catalog
    }

    public func register(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            ListAgentSessionsTool(
                catalog: catalog
            )
            ReadAgentSessionTool(
                catalog: catalog
            )
            ReadAgentTranscriptTool(
                catalog: catalog
            )
            ReadAgentApprovalsTool(
                catalog: catalog
            )
            ListAgentArtifactsTool(
                catalog: catalog
            )
            ReadAgentArtifactTool(
                catalog: catalog
            )
            ListAgentPreparedIntentsTool(
                catalog: catalog
            )
            ReadAgentPreparedIntentTool(
                catalog: catalog
            )
        }
    }
}
