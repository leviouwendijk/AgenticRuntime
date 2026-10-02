import Agentic
import Workspace
import Primitives
import Schema
import Macros

@JSONSchema
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

@JSONSchema
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

public struct ReadAgentSessionTool: Tool {
    public typealias Input = ReadAgentSessionToolInput
    public typealias Output = ReadAgentSessionToolOutput

    public static let identifier: ToolIdentifier = "read_agent_session"
    public static let description = "Read Agentic session metadata and lightweight inspection counts."
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
            summary: "Read Agentic session \(input.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        workspace: WorkspaceContext?
    ) async throws -> Output {

        let summary = try catalog.loadSession(
            sessionID: input.sessionID
        )

        let inspection = input.includeInspection
            ? try await catalog.inspectSession(
                sessionID: input.sessionID
            )
            : nil

        return ReadAgentSessionToolOutput(
                summary: summary,
                inspection: inspection
            )
    }
}