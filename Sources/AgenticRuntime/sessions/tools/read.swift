import Agentic
import Primitives
import Schema
import Macros

public extension Sessions.Tools {
    @Tool("read_agent_session")
    struct Read: Tool {
        @JSONSchema
        public struct Input: HashableSource {
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
        public struct Output: HashableResult {
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

        public static let purpose = "Read Agentic session metadata and lightweight inspection counts."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Read Agentic session \(input.sessionID).",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let catalog = try context.require(AgentSessionCatalog.self)

            return Output(
                summary: try catalog.loadSession(
                    sessionID: input.sessionID
                ),
                inspection: input.includeInspection
                    ? try await catalog.inspectSession(
                        sessionID: input.sessionID
                    )
                    : nil
            )
        }
    }
}
