import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros
import AgenticTools

@JSONSchema
public struct ListAgentArtifactsToolInput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let kinds: [AgentArtifactKind]
    public let latestFirst: Bool
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

public struct ListAgentArtifactsToolOutput: Sendable, Codable, Hashable {
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

public struct ListAgentArtifactsTool: AgentTool {
    public typealias Input = ListAgentArtifactsToolInput
    public typealias Output = ListAgentArtifactsToolOutput

    public static let identifier: AgentToolIdentifier = "list_agent_artifacts"
    public static let description = "List artifacts emitted for a durable Agentic session."
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
            summary: "List artifacts for session \(input.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        let artifacts = try await catalog.listArtifacts(
            sessionID: input.sessionID,
            kinds: input.kinds,
            latestFirst: input.latestFirst,
            limit: nil
        )
        let returnedArtifacts = Array(
            artifacts.prefix(
                input.clampedLimit
            )
        )

        return ListAgentArtifactsToolOutput(
                sessionID: input.sessionID,
                totalArtifactCount: artifacts.count,
                artifacts: returnedArtifacts
            )
    }
}