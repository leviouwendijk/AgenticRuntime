import Agentic
import AgenticExecution
import Workspace
import Primitives
import Schema
import Macros

@JSONSchema
public struct ReadAgentApprovalsToolInput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let limit: Int?
    public let latestFirst: Bool

    public init(
        sessionID: String,
        limit: Int? = nil,
        latestFirst: Bool = false
    ) {
        self.sessionID = sessionID
        self.limit = limit
        self.latestFirst = latestFirst
    }
}

@JSONSchema
public struct ReadAgentApprovalsToolOutput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let totalEventCount: Int
    public let returnedEventCount: Int
    public let events: [AgentApprovalEvent]

    public init(
        sessionID: String,
        totalEventCount: Int,
        events: [AgentApprovalEvent]
    ) {
        self.sessionID = sessionID
        self.totalEventCount = totalEventCount
        self.returnedEventCount = events.count
        self.events = events
    }
}

public struct ReadAgentApprovalsTool: Tool {
    public typealias Input = ReadAgentApprovalsToolInput
    public typealias Output = ReadAgentApprovalsToolOutput

    public static let identifier: ToolIdentifier = "read_agent_approvals"
    public static let description = "Read approval/audit events for a durable Agentic session."
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
            summary: "Read approval events for session \(input.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        workspace: WorkspaceContext?
    ) async throws -> Output {

        var events = try await catalog.loadApprovals(
            sessionID: input.sessionID
        )

        let total = events.count

        if input.latestFirst {
            events.reverse()
        }

        let limit = max(
            0,
            input.limit ?? 100
        )

        events = Array(
            events.prefix(limit)
        )

        return ReadAgentApprovalsToolOutput(
                sessionID: input.sessionID,
                totalEventCount: total,
                events: events
            )
    }
}