import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

@JSONSchema
public struct ReadPreparedIntentToolInput: Sendable, Codable, Hashable {
    public let id: PreparedIntentIdentifier

    public init(
        id: PreparedIntentIdentifier
    ) {
        self.id = id
    }
}

public struct ReadPreparedIntentToolOutput: Sendable, Codable, Hashable {
    public let intent: PreparedIntent

    public init(
        intent: PreparedIntent
    ) {
        self.intent = intent
    }
}

public struct ReadPreparedIntentTool: AgentTool {
    public typealias Input = ReadPreparedIntentToolInput
    public typealias Output = ReadPreparedIntentToolOutput

    public static let identifier: AgentToolIdentifier = "read_prepared_intent"
    public static let description = "Read a prepared intent and its exact review payload."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier { Self.identifier }
    public var description: String { Self.description }
    public var risk: ActionRisk { Self.risk }

    public let manager: PreparedIntentManager

    public init(
        manager: PreparedIntentManager
    ) {
        self.manager = manager
    }

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            summary: "Read prepared intent \(input.id.rawValue).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        return ReadPreparedIntentToolOutput(
                intent: try await manager.get(
                    input.id
                )
            )
    }
}