import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

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
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            ReadPreparedIntentToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Read prepared intent \(decoded.id.rawValue).",
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            ReadPreparedIntentToolInput.self,
            from: input
        )

        return try JSONToolBridge.encode(
            ReadPreparedIntentToolOutput(
                intent: try await manager.get(
                    decoded.id
                )
            )
        )
    }
}
