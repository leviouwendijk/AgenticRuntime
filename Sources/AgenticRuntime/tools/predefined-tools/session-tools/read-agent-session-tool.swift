import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

public struct ReadAgentSessionToolInput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let includeInspection: Bool

    public init(
        sessionID: String,
        includeInspection: Bool = true
    ) {
        self.sessionID = sessionID
        self.includeInspection = includeInspection
    }
}

public struct ReadAgentSessionToolOutput: Sendable, Codable, Hashable {
    public let summary: AgentSessionSummary
    public let inspection: AgentSessionInspection?

    public init(
        summary: AgentSessionSummary,
        inspection: AgentSessionInspection? = nil
    ) {
        self.summary = summary
        self.inspection = inspection
    }
}

public struct ReadAgentSessionTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "read_agent_session"
    public static let description = "Read Agentic session metadata and lightweight inspection counts."
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
            ReadAgentSessionToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Read Agentic session \(decoded.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            ReadAgentSessionToolInput.self,
            from: input
        )

        let summary = try catalog.loadSession(
            sessionID: decoded.sessionID
        )

        let inspection = decoded.includeInspection
            ? try await catalog.inspectSession(
                sessionID: decoded.sessionID
            )
            : nil

        return try JSONToolBridge.encode(
            ReadAgentSessionToolOutput(
                summary: summary,
                inspection: inspection
            )
        )
    }
}
