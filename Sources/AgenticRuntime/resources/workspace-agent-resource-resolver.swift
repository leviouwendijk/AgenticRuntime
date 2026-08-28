import Agentic
import AgenticWorkspace
import Foundation
import Path

public struct WorkspaceAgentResourceResolver:
    AgentResourceResolver
{
    public let workspace: AgentWorkspace
    public let rootID: PathAccessRootIdentifier
    public let toolName: String

    public init(
        workspace: AgentWorkspace,
        rootID: PathAccessRootIdentifier = .project,
        toolName: String = "resource_resolver"
    ) {
        self.workspace = workspace
        self.rootID = rootID
        self.toolName = toolName
    }

    public func resolve(
        _ resource: AgentResource
    ) async throws -> ResolvedAgentResource {
        let authorized = try authorizedPath(
            for: resource
        )
        let read = try workspace.readData(
            authorized.path
        )

        guard read.existed else {
            throw WorkspaceAgentResourceResolutionError.missingResource(
                authorized.presentationPath
            )
        }

        var resource = resource
        resource.byteCount = read.byteCount

        if resource.metadata.filename == nil {
            resource.metadata.filename =
                authorized.absoluteURL.lastPathComponent
        }

        return .init(
            resource: resource,
            data: read.data
        )
    }
}

private extension WorkspaceAgentResourceResolver {
    func authorizedPath(
        for resource: AgentResource
    ) throws -> AgenticAuthorizedPath {
        switch resource.source.kind {
        case .reference:
            return try workspace.accessController.authorize(
                rootID: rootID,
                path: resource.source.value,
                capability: .read,
                toolName: toolName,
                type: .file
            )

        case .uri:
            guard let url = URL(
                string: resource.source.value
            ) else {
                throw WorkspaceAgentResourceResolutionError.invalidURI(
                    resource.source.value
                )
            }

            guard url.isFileURL else {
                throw WorkspaceAgentResourceResolutionError.unsupportedURI(
                    resource.source.value
                )
            }

            return try workspace.accessController.authorize(
                rootID: rootID,
                url: url,
                capability: .read,
                toolName: toolName,
                type: .file
            )
        }
    }
}

public enum WorkspaceAgentResourceResolutionError:
    Error,
    Sendable,
    LocalizedError,
    Equatable
{
    case invalidURI(String)
    case unsupportedURI(String)
    case missingResource(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURI(let value):
            return "Invalid resource URI: \(value)"

        case .unsupportedURI(let value):
            return "Workspace resource resolution supports file URIs only: \(value)"

        case .missingResource(let path):
            return "Resource does not exist at authorized workspace path '\(path)'."
        }
    }
}
