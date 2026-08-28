import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

public struct ReadAgentTranscriptToolInput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let startIndex: Int?
    public let limit: Int?
    public let latestFirst: Bool

    public init(
        sessionID: String,
        startIndex: Int? = nil,
        limit: Int? = nil,
        latestFirst: Bool = false
    ) {
        self.sessionID = sessionID
        self.startIndex = startIndex
        self.limit = limit
        self.latestFirst = latestFirst
    }
}

public struct ReadAgentTranscriptToolOutput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let totalEventCount: Int
    public let returnedEventCount: Int
    public let events: [AgentTranscriptEvent]

    public init(
        sessionID: String,
        totalEventCount: Int,
        events: [AgentTranscriptEvent]
    ) {
        self.sessionID = sessionID
        self.totalEventCount = totalEventCount
        self.returnedEventCount = events.count
        self.events = events
    }
}

public struct ReadAgentTranscriptTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "read_agent_transcript"
    public static let description = "Read transcript events for a durable Agentic session."
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
            ReadAgentTranscriptToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Read transcript events for session \(decoded.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            ReadAgentTranscriptToolInput.self,
            from: input
        )

        var events = try await catalog.loadTranscript(
            sessionID: decoded.sessionID
        )

        let total = events.count

        if decoded.latestFirst {
            events.reverse()
        }

        let start = max(
            0,
            decoded.startIndex ?? 0
        )
        let limit = max(
            0,
            decoded.limit ?? 100
        )

        events = Array(
            events.dropFirst(start).prefix(limit)
        )

        return try JSONToolBridge.encode(
            ReadAgentTranscriptToolOutput(
                sessionID: decoded.sessionID,
                totalEventCount: total,
                events: events
            )
        )
    }
}
