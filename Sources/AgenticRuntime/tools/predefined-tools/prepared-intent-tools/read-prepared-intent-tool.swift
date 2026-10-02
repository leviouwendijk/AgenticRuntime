import Agentic
import Workspace
import Primitives
import Schema
import Macros

@JSONSchema
public struct ReadPreparedIntentToolInput: Sendable, Codable, Hashable {
    public let id: PreparedIntentIdentifier

    public init(
        id: PreparedIntentIdentifier
    ) {
        self.id = id
    }
}

@JSONSchema
public struct ReadPreparedIntentToolOutput: Sendable, Codable, Hashable {
    public let intent: PreparedIntent

    public init(
        intent: PreparedIntent
    ) {
        self.intent = intent
    }
}

public struct ReadPreparedIntentTool: Tool {
    public typealias Input = ReadPreparedIntentToolInput
    public typealias Output = ReadPreparedIntentToolOutput

    public static let identifier: ToolIdentifier = "read_prepared_intent"
    public static let description = "Read a prepared intent and its exact review payload."
    public static let risk: ActionRisk = .observe

    public static let definition: ToolDefinition = .init(
        identifier: Self.identifier,
        purpose: Self.description,
        risk: Self.risk
    )

    public var identifier: ToolIdentifier { Self.identifier }
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
        workspace: WorkspaceContext?
    ) async throws -> ToolPreflight {

        return .init(
            tool: Self.definition.identifier,
            risk: Self.definition.risk,
            summary: "Read prepared intent \(input.id.rawValue).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        workspace: WorkspaceContext?
    ) async throws -> Output {

        return ReadPreparedIntentToolOutput(
                intent: try await manager.get(
                    input.id
                )
            )
    }
}