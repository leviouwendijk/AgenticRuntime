import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

public struct ComposeContextTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "compose_context"
    public static let description = "Compose a context plan into prompt-ready text using the configured ContextComposer."
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
            ComposeContextToolInput.self,
            from: input
        )
        let inspection = ContextToolSupport.inspect(
            decoded.plan
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: summary(
                inspection: inspection,
                maxCharacters: decoded.maxCharacters
            ),
            estimatedByteCount: inspection.hasUnknownSizeSources
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
            ComposeContextToolInput.self,
            from: input
        )
        let effectiveComposer = ContextComposer(
            workspace: workspace ?? composer.workspace
        )
        let composed = try effectiveComposer.compose(
            decoded.plan
        )
        let trimmed = ContextToolSupport.truncated(
            composed.text,
            maxCharacters: decoded.maxCharacters
        )
        let size = ContextToolSupport.estimate(
            text: trimmed.text
        )

        return try JSONToolBridge.encode(
            ComposeContextToolOutput(
                metadata: composed.metadata,
                content: trimmed.text,
                size: size,
                inspection: ContextToolSupport.inspect(
                    decoded.plan
                ),
                truncated: trimmed.truncated
            )
        )
    }
}

private extension ComposeContextTool {
    func summary(
        inspection: ContextPlanInspection,
        maxCharacters: Int?
    ) -> String {
        var parts = [
            "Compose \(inspection.sourceCount) context source(s)"
        ]

        if inspection.hasFileBackedSources {
            parts.append(
                "including file-backed source(s)"
            )
        }

        if let maxCharacters {
            parts.append(
                "capped at \(maxCharacters) character(s)"
            )
        }

        return parts.joined(separator: ", ")
    }
}
