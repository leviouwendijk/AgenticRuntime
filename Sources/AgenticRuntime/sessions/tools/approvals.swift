import Agentic
import Primitives
import Schema
import Macros

public extension Sessions.Tools {
    @Tool("read_agent_approvals")
    struct Approvals: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let sessionID: String
            /// Defaults to 100 events.
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
        public struct Output: HashableResult {
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

        public static let purpose = "Read approval/audit events for a durable Agentic session."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Read approval events for session \(input.sessionID).",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let catalog = try context.require(AgentSessionCatalog.self)
            var events = try await catalog.loadApprovals(
                sessionID: input.sessionID
            )
            let total = events.count

            if input.latestFirst {
                events.reverse()
            }

            return Output(
                sessionID: input.sessionID,
                totalEventCount: total,
                events: Array(events.prefix(max(0, input.limit ?? 100)))
            )
        }
    }
}
