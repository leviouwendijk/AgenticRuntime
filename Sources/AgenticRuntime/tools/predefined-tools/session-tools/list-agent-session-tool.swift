import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

@JSONSchema
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
    public typealias Input = ListAgentSessionsToolInput
    public typealias Output = ListAgentSessionsToolOutput

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
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            summary: input.parentSessionID == nil
                ? "List Agentic sessions."
                : "List Agentic child branches for session \(input.parentSessionID ?? "").",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        let sessions: [AgentSessionSummary]

        if let parentSessionID = input.parentSessionID,
           !parentSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessions = try catalog.listBranches(
                parentSessionID: parentSessionID
            )
        } else {
            sessions = try catalog.listSessions(
                statuses: input.statuses,
                includeArchived: input.includeArchived
            )
        }

        return ListAgentSessionsToolOutput(
                sessions: sessions
            )
    }
}