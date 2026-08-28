import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

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

public struct ReadAgentApprovalsTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "read_agent_approvals"
    public static let description = "Read approval/audit events for a durable Agentic session."
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
            ReadAgentApprovalsToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Read approval events for session \(decoded.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            ReadAgentApprovalsToolInput.self,
            from: input
        )

        var events = try await catalog.loadApprovals(
            sessionID: decoded.sessionID
        )

        let total = events.count

        if decoded.latestFirst {
            events.reverse()
        }

        let limit = max(
            0,
            decoded.limit ?? 100
        )

        events = Array(
            events.prefix(limit)
        )

        return try JSONToolBridge.encode(
            ReadAgentApprovalsToolOutput(
                sessionID: decoded.sessionID,
                totalEventCount: total,
                events: events
            )
        )
    }
}
