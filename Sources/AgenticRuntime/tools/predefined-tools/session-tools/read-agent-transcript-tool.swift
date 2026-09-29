import Agentic
import AgenticExecution
import Workspace
import Primitives
import Schema
import Macros

@JSONSchema
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

@JSONSchema
public struct ReadAgentTranscriptToolOutput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let totalEventCount: Int
    public let returnedEventCount: Int
    public let events: [TranscriptEvent]

    public init(
        sessionID: String,
        totalEventCount: Int,
        events: [TranscriptEvent]
    ) {
        self.sessionID = sessionID
        self.totalEventCount = totalEventCount
        self.returnedEventCount = events.count
        self.events = events
    }
}

public struct ReadAgentTranscriptTool: Tool {
    public typealias Input = ReadAgentTranscriptToolInput
    public typealias Output = ReadAgentTranscriptToolOutput

    public static let identifier: ToolIdentifier = "read_agent_transcript"
    public static let description = "Read transcript events for a durable Agentic session."
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
        workspace: WorkspaceContext?
    ) async throws -> ToolPreflight {

        return .init(
            tool: Self.definition.identifier,
            risk: Self.definition.risk,
            summary: "Read transcript events for session \(input.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        workspace: WorkspaceContext?
    ) async throws -> Output {

        var events = try await catalog.loadTranscript(
            sessionID: input.sessionID
        )

        let total = events.count

        if input.latestFirst {
            events.reverse()
        }

        let start = max(
            0,
            input.startIndex ?? 0
        )
        let limit = max(
            0,
            input.limit ?? 100
        )

        events = Array(
            events.dropFirst(start).prefix(limit)
        )

        return ReadAgentTranscriptToolOutput(
                sessionID: input.sessionID,
                totalEventCount: total,
                events: events
            )
    }
}