import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

public struct EstimateContextSizeTool: AgentTool {
    public typealias Input = EstimateContextSizeToolInput
    public typealias Output = EstimateContextSizeToolOutput

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
            summary: input.shouldCompose
                ? "Compose context internally to estimate final rendered size."
                : "Estimate known context source sizes without rendering file-backed content.",
            estimatedByteCount: input.shouldCompose || inspection.hasUnknownSizeSources
                ? nil
                : inspection.knownCharacterCount,
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let inspection = ContextToolSupport.inspect(
            input.plan
        )

        let size: ContextSizeEstimate?
        if input.shouldCompose {
            let effectiveComposer = ContextComposer(
                workspace: context.workspace ?? composer.workspace
            )
            let composed = try effectiveComposer.compose(
                input.plan
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

        return EstimateContextSizeToolOutput(
                metadata: input.plan.metadata,
                inspection: inspection,
                size: size,
                composed: input.shouldCompose
            )
    }
}