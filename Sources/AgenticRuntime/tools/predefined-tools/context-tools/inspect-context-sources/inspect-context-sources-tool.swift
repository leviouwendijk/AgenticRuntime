import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

public struct InspectContextSourcesTool: AgentTool {
    public typealias Input = InspectContextSourcesToolInput
    public typealias Output = InspectContextSourcesToolOutput

    public static let identifier: AgentToolIdentifier = "inspect_context_sources"
    public static let description = "Inspect a context plan without rendering full context content."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier { Self.identifier }
    public var description: String { Self.description }
    public var risk: ActionRisk { Self.risk }

    public init() {}

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
            summary: "Inspect \(inspection.sourceCount) context source(s) without rendering full content.",
            estimatedByteCount: inspection.knownCharacterCount,
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        return InspectContextSourcesToolOutput(
                metadata: input.plan.metadata,
                inspection: ContextToolSupport.inspect(
                    input.plan
                )
            )
    }
}