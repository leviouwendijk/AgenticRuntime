import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

@JSONSchema
public struct ListAgentPreparedIntentsToolInput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let statuses: [PreparedIntentStatus]
    public let actionType: String?
    public let includeExpired: Bool
    public let limit: Int?

    public init(
        sessionID: String,
        statuses: [PreparedIntentStatus] = [],
        actionType: String? = nil,
        includeExpired: Bool = false,
        limit: Int? = nil
    ) {
        self.sessionID = sessionID
        self.statuses = statuses
        self.actionType = actionType
        self.includeExpired = includeExpired
        self.limit = limit
    }

    public var clampedLimit: Int {
        guard let limit else {
            return 100
        }

        return max(
            0,
            limit
        )
    }
}

public struct ListAgentPreparedIntentsToolOutput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let totalIntentCount: Int
    public let returnedIntentCount: Int
    public let intents: [PreparedIntent]

    public init(
        sessionID: String,
        totalIntentCount: Int,
        intents: [PreparedIntent]
    ) {
        self.sessionID = sessionID
        self.totalIntentCount = totalIntentCount
        self.returnedIntentCount = intents.count
        self.intents = intents
    }
}

public struct ListAgentPreparedIntentsTool: AgentTool {
    public typealias Input = ListAgentPreparedIntentsToolInput
    public typealias Output = ListAgentPreparedIntentsToolOutput

    public static let identifier: AgentToolIdentifier = "list_agent_prepared_intents"
    public static let description = "List prepared intents associated with a durable Agentic session."
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
            summary: "List prepared intents for session \(input.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        let intents = try await catalog.listPreparedIntents(
            sessionID: input.sessionID,
            statuses: input.statuses,
            actionType: input.actionType,
            includeExpired: input.includeExpired,
            limit: nil
        )
        let returned = Array(
            intents.prefix(
                input.clampedLimit
            )
        )

        return ListAgentPreparedIntentsToolOutput(
                sessionID: input.sessionID,
                totalIntentCount: intents.count,
                intents: returned
            )
    }
}