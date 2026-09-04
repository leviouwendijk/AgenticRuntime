import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

public struct ComposeContextTool: AgentTool {
    public typealias Input = ComposeContextToolInput
    public typealias Output = ComposeContextToolOutput

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
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        let inspection = ContextToolSupport.inspect(
            input.plan
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            summary: summary(
                inspection: inspection,
                maxCharacters: input.maxCharacters
            ),
            estimatedByteCount: inspection.hasUnknownSizeSources
                ? nil
                : inspection.knownCharacterCount,
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let effectiveComposer = ContextComposer(
            workspace: context.workspace ?? composer.workspace
        )
        let composed = try effectiveComposer.compose(
            input.plan
        )
        let trimmed = ContextToolSupport.truncated(
            composed.text,
            maxCharacters: input.maxCharacters
        )
        let size = ContextToolSupport.estimate(
            text: trimmed.text
        )

        return ComposeContextToolOutput(
                metadata: composed.metadata,
                content: trimmed.text,
                size: size,
                inspection: ContextToolSupport.inspect(
                    input.plan
                ),
                truncated: trimmed.truncated
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