import Agentic
import Primitives
import Schema
import Macros

public extension Sessions.Tools {
    @Tool("list_agent_artifacts")
    struct Artifacts: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let sessionID: String
            /// An empty array includes every kind.
            public let kinds: [AgentArtifactKind]
            public let latestFirst: Bool
            /// Defaults to 100 artifacts.
            public let limit: Int?

            public init(
                sessionID: String,
                kinds: [AgentArtifactKind] = [],
                latestFirst: Bool = true,
                limit: Int? = nil
            ) {
                self.sessionID = sessionID
                self.kinds = kinds
                self.latestFirst = latestFirst
                self.limit = limit
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let sessionID: String
            public let totalArtifactCount: Int
            public let returnedArtifactCount: Int
            public let artifacts: [AgentArtifact]

            public init(
                sessionID: String,
                totalArtifactCount: Int,
                artifacts: [AgentArtifact]
            ) {
                self.sessionID = sessionID
                self.totalArtifactCount = totalArtifactCount
                self.returnedArtifactCount = artifacts.count
                self.artifacts = artifacts
            }
        }

        public static let purpose = "List artifacts emitted for a durable Agentic session."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "List artifacts for session \(input.sessionID).",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let catalog = try context.require(AgentSessionCatalog.self)
            let artifacts = try await catalog.listArtifacts(
                sessionID: input.sessionID,
                kinds: input.kinds,
                latestFirst: input.latestFirst,
                limit: nil
            )

            return Output(
                sessionID: input.sessionID,
                totalArtifactCount: artifacts.count,
                artifacts: Array(artifacts.prefix(max(0, input.limit ?? 100)))
            )
        }
    }
}
