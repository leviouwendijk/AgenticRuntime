import Agentic
import Primitives
import Schema
import Macros

@JSONSchema
public struct ReadAgentPreparedIntentToolInput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let id: PreparedIntentIdentifier

    public init(
        sessionID: String,
        id: PreparedIntentIdentifier
    ) {
        self.sessionID = sessionID
        self.id = id
    }
}

@JSONSchema
public struct ReadAgentPreparedIntentToolOutput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let intent: PreparedIntent

    public init(
        sessionID: String,
        intent: PreparedIntent
    ) {
        self.sessionID = sessionID
        self.intent = intent
    }
}

public struct ReadAgentPreparedIntentTool: Tool {
    public typealias Input = ReadAgentPreparedIntentToolInput
    public typealias Output = ReadAgentPreparedIntentToolOutput

    public static let identifier: ToolIdentifier = "read_agent_prepared_intent"
    public static let description = "Read a prepared intent associated with a durable Agentic session."
    public static let risk: ActionRisk = .observe

    public static let definition: ToolDefinition = .init(
        identifier: Self.identifier,
        purpose: Self.description,
        risk: Self.risk
    )

    public var identifier: ToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }

    public var risk: ActionRisk {
        Self.risk
    }

    public let catalog: AgentSessionCatalog

    public init(
        catalog: AgentSessionCatalog
    ) {
        self.catalog = catalog
    }

    public func preflight(
        _ input: Input,
        in context: ToolContext
    ) async throws -> ToolPreflight {

        return .init(
            tool: Self.definition.identifier,
            risk: Self.definition.risk,
            summary: "Read prepared intent \(input.id.rawValue) for session \(input.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        in context: ToolContext
    ) async throws -> Output {

        let intent = try await catalog.loadPreparedIntent(
            sessionID: input.sessionID,
            id: input.id
        )

        return ReadAgentPreparedIntentToolOutput(
                sessionID: input.sessionID,
                intent: intent
            )
    }
}