import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

public struct EstimateContextSizeTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "estimate_context_size"
    public static let description = "Estimate context size and approximate token count for a context plan."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier { Self.identifier }
    public var description: String { Self.description }
    public var risk: ActionRisk { Self.risk }

    public let composer: ContextComposer

    public init(
        composer: ContextComposer = .init()
    ) {
        self.composer = composer
    }

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            EstimateContextSizeToolInput.self,
            from: input
        )
        let inspection = ContextToolSupport.inspect(
            decoded.plan
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: decoded.shouldCompose
                ? "Compose context internally to estimate final rendered size."
                : "Estimate known context source sizes without rendering file-backed content.",
            estimatedByteCount: decoded.shouldCompose || inspection.hasUnknownSizeSources
                ? nil
                : inspection.knownCharacterCount,
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            EstimateContextSizeToolInput.self,
            from: input
        )
        let inspection = ContextToolSupport.inspect(
            decoded.plan
        )

        let size: ContextSizeEstimate?
        if decoded.shouldCompose {
            let effectiveComposer = ContextComposer(
                workspace: workspace ?? composer.workspace
            )
            let composed = try effectiveComposer.compose(
                decoded.plan
            )

            size = ContextToolSupport.estimate(
                text: composed.text
            )
        } else {
            size = .init(
                characterCount: inspection.knownCharacterCount,
                byteCount: inspection.knownCharacterCount,
                lineCount: 0,
                approximateTokenCount: inspection.knownApproximateTokenCount
            )
        }

        return try JSONToolBridge.encode(
            EstimateContextSizeToolOutput(
                metadata: decoded.plan.metadata,
                inspection: inspection,
                size: size,
                composed: decoded.shouldCompose
            )
        )
    }
}
