import Agentic
import IO
import Workspace
import Foundation
import Path

public struct WorkspaceAgentResourceResolver:
    AgentResourceResolver
{
    public let workspace: Workspace
    public let rootID: PathAccessRootIdentifier
    public let toolName: String

    public init(
        workspace: Workspace,
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
        let authorization = try authorization(
            for: resource
        )
        let authorized = authorization.authorizedPath

        guard FileSystem.default.exists(authorized.absoluteURL) else {
            throw WorkspaceAgentResourceResolutionError.missingResource(
                authorized.presentationPath
            )
        }

        let data = try Data(
            contentsOf: authorized.absoluteURL
        )
        var resource = resource
        resource.byteCount = data.count

        if resource.metadata.filename == nil {
            resource.metadata.filename =
                authorized.absoluteURL.lastPathComponent
        }

        return .init(
            resource: resource,
            data: data
        )
    }
}

private extension WorkspaceAgentResourceResolver {
    func authorization(
        for resource: AgentResource
    ) throws -> WorkspaceAuthorization {
        let path: String

        switch resource.source.kind {
        case .reference:
            path = resource.source.value

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

            path = try relativePath(
                for: url
            )
        }

        return try workspace.authorize(
            path,
            rootIdentifier: rootID,
            capability: .read
        )
    }

    func relativePath(
        for url: URL
    ) throws -> String {
        guard let root = workspace.root(
            identifier: rootID
        ) else {
            throw WorkspaceAgentResourceResolutionError
                .rootUnavailable(
                    rootID.rawValue
                )
        }

        let rootURL = root.rootURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidate = url
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = rootURL.path
        let candidatePath = candidate.path

        guard candidatePath != rootPath else {
            throw WorkspaceAgentResourceResolutionError
                .resourceOutsideRoot(
                    candidatePath
                )
        }

        let prefix = rootPath.hasSuffix("/")
            ? rootPath
            : rootPath + "/"

        guard candidatePath.hasPrefix(
            prefix
        ) else {
            throw WorkspaceAgentResourceResolutionError
                .resourceOutsideRoot(
                    candidatePath
                )
        }

        return String(
            candidatePath.dropFirst(
                prefix.count
            )
        )
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
    case rootUnavailable(String)
    case resourceOutsideRoot(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURI(let value):
            return "Invalid resource URI: \(value)"

        case .unsupportedURI(let value):
            return "Workspace resource resolution supports file URIs only: \(value)"

        case .missingResource(let path):
            return "Resource does not exist at authorized workspace path '\(path)'."

        case .rootUnavailable(let identifier):
            return "Workspace resource root '\(identifier)' is not available."

        case .resourceOutsideRoot(let path):
            return "Workspace resource URI is outside the configured resource root: \(path)"
        }
    }
}
