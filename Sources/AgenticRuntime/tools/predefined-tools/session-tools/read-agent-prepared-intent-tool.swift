import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

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

public struct ReadAgentPreparedIntentTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "read_agent_prepared_intent"
    public static let description = "Read a prepared intent associated with a durable Agentic session."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier {
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
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            ReadAgentPreparedIntentToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Read prepared intent \(decoded.id.rawValue) for session \(decoded.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            ReadAgentPreparedIntentToolInput.self,
            from: input
        )

        let intent = try await catalog.loadPreparedIntent(
            sessionID: decoded.sessionID,
            id: decoded.id
        )

        return try JSONToolBridge.encode(
            ReadAgentPreparedIntentToolOutput(
                sessionID: decoded.sessionID,
                intent: intent
            )
        )
    }
}
