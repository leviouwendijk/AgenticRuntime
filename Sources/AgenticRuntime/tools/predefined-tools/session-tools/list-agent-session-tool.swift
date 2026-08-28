import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

public struct ListAgentSessionsToolInput: Sendable, Codable, Hashable {
    public let statuses: [AgentSessionStatus]
    public let includeArchived: Bool
    public let parentSessionID: String?

    public init(
        statuses: [AgentSessionStatus] = [],
        includeArchived: Bool = false,
        parentSessionID: String? = nil
    ) {
        self.statuses = statuses
        self.includeArchived = includeArchived
        self.parentSessionID = parentSessionID
    }
}

public struct ListAgentSessionsToolOutput: Sendable, Codable, Hashable {
    public let sessions: [AgentSessionSummary]
    public let count: Int

    public init(
        sessions: [AgentSessionSummary]
    ) {
        self.sessions = sessions
        self.count = sessions.count
    }
}

public struct ListAgentSessionsTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "list_agent_sessions"
    public static let description = "List durable Agentic sessions and branches."
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
            ListAgentSessionsToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: decoded.parentSessionID == nil
                ? "List Agentic sessions."
                : "List Agentic child branches for session \(decoded.parentSessionID ?? "").",
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            ListAgentSessionsToolInput.self,
            from: input
        )

        let sessions: [AgentSessionSummary]

        if let parentSessionID = decoded.parentSessionID,
           !parentSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessions = try catalog.listBranches(
                parentSessionID: parentSessionID
            )
        } else {
            sessions = try catalog.listSessions(
                statuses: decoded.statuses,
                includeArchived: decoded.includeArchived
            )
        }

        return try JSONToolBridge.encode(
            ListAgentSessionsToolOutput(
                sessions: sessions
            )
        )
    }
}
