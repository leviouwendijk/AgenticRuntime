import Agentic
import AgenticExecution
import Workspace
import Primitives
import Schema
import Macros

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

@JSONSchema
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

public struct ListAgentSessionsTool: Tool {
    public typealias Input = ListAgentSessionsToolInput
    public typealias Output = ListAgentSessionsToolOutput

    public static let identifier: ToolIdentifier = "list_agent_sessions"
    public static let description = "List durable Agentic sessions and branches."
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
            summary: input.parentSessionID == nil
                ? "List Agentic sessions."
                : "List Agentic child branches for session \(input.parentSessionID ?? "").",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        workspace: WorkspaceContext?
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