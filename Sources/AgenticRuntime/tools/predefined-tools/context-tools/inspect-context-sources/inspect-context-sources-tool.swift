import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

public struct InspectContextSourcesTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "inspect_context_sources"
    public static let description = "Inspect a context plan without rendering full context content."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier { Self.identifier }
    public var description: String { Self.description }
    public var risk: ActionRisk { Self.risk }

    public init() {}

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            InspectContextSourcesToolInput.self,
            from: input
        )
        let inspection = ContextToolSupport.inspect(
            decoded.plan
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Inspect \(inspection.sourceCount) context source(s) without rendering full content.",
            estimatedByteCount: inspection.knownCharacterCount,
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            InspectContextSourcesToolInput.self,
            from: input
        )

        return try JSONToolBridge.encode(
            InspectContextSourcesToolOutput(
                metadata: decoded.plan.metadata,
                inspection: ContextToolSupport.inspect(
                    decoded.plan
                )
            )
        )
    }
}
