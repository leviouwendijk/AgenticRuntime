import Agentic
import Primitives
import Schema
import Macros

public extension Sessions.Tools {
    @Tool("read_agent_transcript")
    struct Transcript: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let sessionID: String
            public let startIndex: Int?
            /// Defaults to 100 events.
            public let limit: Int?
            public let latestFirst: Bool

            public init(
                sessionID: String,
                startIndex: Int? = nil,
                limit: Int? = nil,
                latestFirst: Bool = false
            ) {
                self.sessionID = sessionID
                self.startIndex = startIndex
                self.limit = limit
                self.latestFirst = latestFirst
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let sessionID: String
            public let totalEventCount: Int
            public let returnedEventCount: Int
            public let events: [TranscriptEvent]

            public init(
                sessionID: String,
                totalEventCount: Int,
                events: [TranscriptEvent]
            ) {
                self.sessionID = sessionID
                self.totalEventCount = totalEventCount
                self.returnedEventCount = events.count
                self.events = events
            }
        }

        public static let purpose = "Read transcript events for a durable Agentic session."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Read transcript events for session \(input.sessionID).",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let catalog = try context.require(AgentSessionCatalog.self)
            var events = try await catalog.loadTranscript(
                sessionID: input.sessionID
            )
            let total = events.count

            if input.latestFirst {
                events.reverse()
            }

            let start = max(0, input.startIndex ?? 0)
            let limit = max(0, input.limit ?? 100)

            return Output(
                sessionID: input.sessionID,
                totalEventCount: total,
                events: Array(events.dropFirst(start).prefix(limit))
            )
        }
    }
}
