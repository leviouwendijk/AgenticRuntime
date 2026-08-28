import Foundation
import Path

public struct AgentProjectLayout: Sendable, Codable, Hashable {
    public let root: URL
    public let schema: AgentProjectTreeSchema

    public init(
        root: URL,
        schema: AgentProjectTreeSchema = .init()
    ) {
        self.root = root.standardizedFileURL
        self.schema = schema
    }

    public var tree: PathTree {
        schema.tree
    }

    public var projectConfigurationFileURL: URL {
        fileURL(for: schema.projectConfigurationFile)
    }

    public var localConfigurationFileURL: URL {
        fileURL(for: schema.localConfigurationFile)
    }

    public var localdir: URL {
        directoryURL(for: schema.localdir)
    }

    public var runtimeStorage: AgentRuntimeStorageLayout {
        .init(
            root: root,
            schema: schema.storage
        )
    }

    public var projectRootGitIgnoreEntries: [String] {
        schema.projectRootGitIgnoreEntries
    }

    public func createInitialDirectories() throws {
        try createDirectories(
            schema.initialDirectories.map(directoryURL)
        )
    }

    public func createBaseDirectories() throws {
        try createDirectories(
            [
                directoryURL(
                    for: schema.root
                ),
                localdir
            ]
        )

        try runtimeStorage.createBaseDirectories()
    }

    public func createSessionDirectories(
        sessionID: String
    ) throws {
        try runtimeStorage.createSessionDirectories(
            sessionID: sessionID
        )
    }
}

public extension AgentProjectLayout {
    func directoryURL(
        for address: PathTreeDirectoryAddress
    ) -> URL {
        address.path
            .url(
                base: root,
                filetype: false
            )
            .standardizedFileURL
    }

    func fileURL(
        for address: PathTreeFileAddress
    ) -> URL {
        address.path
            .url(
                base: root,
                filetype: true
            )
            .standardizedFileURL
    }
}

private extension AgentProjectLayout {
    func createDirectories(
        _ urls: [URL]
    ) throws {
        try PathCreation.directories(
            at: urls
        )
    }
}
