import Agentic
import Primitives
import Schema
import Macros

public extension Sessions.Tools {
    @Tool("read_agent_artifact")
    struct Artifact: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let sessionID: String
            public let id: String
            public let includeContent: Bool
            /// Truncates content beyond this many characters.
            public let maxCharacters: Int?

            public init(
                sessionID: String,
                id: String,
                includeContent: Bool = true,
                maxCharacters: Int? = nil
            ) {
                self.sessionID = sessionID
                self.id = id
                self.includeContent = includeContent
                self.maxCharacters = maxCharacters
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let sessionID: String
            public let artifact: AgentArtifact
            public let content: String?
            public let truncated: Bool

            public init(
                sessionID: String,
                artifact: AgentArtifact,
                content: String?,
                truncated: Bool
            ) {
                self.sessionID = sessionID
                self.artifact = artifact
                self.content = content
                self.truncated = truncated
            }
        }

        public static let purpose = "Read an artifact emitted for a durable Agentic session."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Read artifact \(input.id) for session \(input.sessionID).",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let catalog = try context.require(AgentSessionCatalog.self)
            let record = try await catalog.loadArtifact(
                sessionID: input.sessionID,
                id: input.id
            )

            guard input.includeContent else {
                return Output(
                    sessionID: input.sessionID,
                    artifact: record.artifact,
                    content: nil,
                    truncated: false
                )
            }

            let limit = input.maxCharacters.map { max(0, $0) }
            let truncated = limit.map { record.content.count > $0 } ?? false

            return Output(
                sessionID: input.sessionID,
                artifact: record.artifact,
                content: truncated
                    ? String(record.content.prefix(limit ?? 0))
                    : record.content,
                truncated: truncated
            )
        }
    }
}
