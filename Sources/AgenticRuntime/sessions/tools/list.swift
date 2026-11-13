import Agentic
import Primitives
import Schema
import Macros

public extension Sessions.Tools {
    @Tool("list_agent_sessions")
    struct List: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let statuses: [AgentSessionStatus]
            public let includeArchived: Bool
            /// Lists the child branches of this session instead.
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
        public struct Output: HashableResult {
            public let sessions: [AgentSessionSummary]
            public let count: Int

            public init(
                sessions: [AgentSessionSummary]
            ) {
                self.sessions = sessions
                self.count = sessions.count
            }
        }

        public static let purpose = "List durable Agentic sessions and branches."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
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
            in context: ToolContext
        ) async throws -> Output {
            let catalog = try context.require(AgentSessionCatalog.self)

            if let parentSessionID = input.parentSessionID,
               !parentSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Output(
                    sessions: try catalog.listBranches(
                        parentSessionID: parentSessionID
                    )
                )
            }

            return Output(
                sessions: try catalog.listSessions(
                    statuses: input.statuses,
                    includeArchived: input.includeArchived
                )
            )
        }
    }
}
