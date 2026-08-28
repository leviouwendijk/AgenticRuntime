import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

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
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            ListAgentArtifactsToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "List artifacts for session \(decoded.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            ListAgentArtifactsToolInput.self,
            from: input
        )

        let artifacts = try await catalog.listArtifacts(
            sessionID: decoded.sessionID,
            kinds: decoded.kinds,
            latestFirst: decoded.latestFirst,
            limit: nil
        )
        let returnedArtifacts = Array(
            artifacts.prefix(
                decoded.clampedLimit
            )
        )

        return try JSONToolBridge.encode(
            ListAgentArtifactsToolOutput(
                sessionID: decoded.sessionID,
                totalArtifactCount: artifacts.count,
                artifacts: returnedArtifacts
            )
        )
    }
}
