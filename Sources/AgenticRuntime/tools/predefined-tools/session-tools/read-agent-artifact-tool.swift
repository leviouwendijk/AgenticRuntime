import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

@JSONSchema
public struct ReadAgentArtifactToolInput: Sendable, Codable, Hashable {
    public let sessionID: String
    public let id: String
    public let includeContent: Bool
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

    public var clampedMaxCharacters: Int? {
        guard let maxCharacters else {
            return nil
        }

        return max(
            0,
            maxCharacters
        )
    }
}

public struct ReadAgentArtifactToolOutput: Sendable, Codable, Hashable {
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

public struct ReadAgentArtifactTool: AgentTool {
    public typealias Input = ReadAgentArtifactToolInput
    public typealias Output = ReadAgentArtifactToolOutput

    public static let identifier: AgentToolIdentifier = "read_agent_artifact"
    public static let description = "Read an artifact emitted for a durable Agentic session."
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
            summary: "Read artifact \(input.id) for session \(input.sessionID).",
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        let record = try await catalog.loadArtifact(
            sessionID: input.sessionID,
            id: input.id
        )

        let content: String?
        let truncated: Bool

        if input.includeContent {
            let limited = limitedContent(
                record.content,
                maxCharacters: input.clampedMaxCharacters
            )

            content = limited.content
            truncated = limited.truncated
        } else {
            content = nil
            truncated = false
        }

        return ReadAgentArtifactToolOutput(
                sessionID: input.sessionID,
                artifact: record.artifact,
                content: content,
                truncated: truncated
            )
    }
}

private extension ReadAgentArtifactTool {
    func limitedContent(
        _ value: String,
        maxCharacters: Int?
    ) -> (content: String, truncated: Bool) {
        guard let maxCharacters else {
            return (
                value,
                false
            )
        }

        guard value.count > maxCharacters else {
            return (
                value,
                false
            )
        }

        return (
            String(
                value.prefix(
                    maxCharacters
                )
            ),
            true
        )
    }
}