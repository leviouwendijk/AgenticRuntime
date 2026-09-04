import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

@JSONSchema
public struct ListPreparedIntentsToolInput: Sendable, Codable, Hashable {
    public let statuses: [PreparedIntentStatus]
    public let sessionID: String?
    public let actionType: String?
    public let includeExpired: Bool
    public let limit: Int?

    public init(
        statuses: [PreparedIntentStatus] = [],
        sessionID: String? = nil,
        actionType: String? = nil,
        includeExpired: Bool = false,
        limit: Int? = nil
    ) {
        self.statuses = statuses
        self.sessionID = sessionID
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

public struct ListPreparedIntentsToolOutput: Sendable, Codable, Hashable {
    public let totalIntentCount: Int
    public let returnedIntentCount: Int
    public let intents: [PreparedIntent]

    public init(
        totalIntentCount: Int,
        intents: [PreparedIntent]
    ) {
        self.totalIntentCount = totalIntentCount
        self.returnedIntentCount = intents.count
        self.intents = intents
    }
}

public struct ListPreparedIntentsTool: AgentTool {
    public typealias Input = ListPreparedIntentsToolInput
    public typealias Output = ListPreparedIntentsToolOutput

    public static let identifier: AgentToolIdentifier = "list_prepared_intents"
    public static let description = "List prepared intents awaiting review or already resolved."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier { Self.identifier }
    public var description: String { Self.description }
    public var risk: ActionRisk { Self.risk }

    public let manager: PreparedIntentManager

    public init(
        manager: PreparedIntentManager
    ) {
        self.manager = manager
    }

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            summary: summary(
                for: input
            ),
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        let intents = try await manager.list(
            statuses: input.statuses,
            sessionID: input.sessionID,
            actionType: input.actionType,
            includeExpired: input.includeExpired
        )
        let returned = Array(
            intents.prefix(
                input.clampedLimit
            )
        )

        return ListPreparedIntentsToolOutput(
                totalIntentCount: intents.count,
                intents: returned
            )
    }
}

private extension ListPreparedIntentsTool {
    func summary(
        for input: ListPreparedIntentsToolInput
    ) -> String {
        var parts = [
            "List prepared intents"
        ]

        if !input.statuses.isEmpty {
            parts.append(
                "statuses=\(input.statuses.map(\.rawValue).joined(separator: ","))"
            )
        }

        if let sessionID = input.sessionID {
            parts.append(
                "sessionID=\(sessionID)"
            )
        }

        if let actionType = input.actionType {
            parts.append(
                "actionType=\(actionType)"
            )
        }

        return parts.joined(
            separator: " "
        )
    }
}