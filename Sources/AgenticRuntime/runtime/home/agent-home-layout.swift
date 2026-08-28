import Foundation
import Path

public struct AgentHomeLayout: Sendable, Codable, Hashable {
    public let root: URL
    public let schema: AgentHomeTreeSchema

    public init(
        root: URL,
        schema: AgentHomeTreeSchema = .init()
    ) {
        self.root = root.standardizedFileURL
        self.schema = schema
    }

    public var tree: PathTree {
        schema.tree
    }

    public var configfile: URL {
        fileURL(for: schema.configfile)
    }

    public var profilesdir: URL {
        directoryURL(for: schema.profilesdir)
    }

    public var runtimeStorage: AgentRuntimeStorageLayout {
        .init(
            root: root,
            schema: schema.storage
        )
    }

    public func createBaseDirectories() throws {
        try createDirectories(
            [
                directoryURL(
                    for: schema.root
                ),
                profilesdir
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

public extension AgentHomeLayout {
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

private extension AgentHomeLayout {
    func createDirectories(
        _ urls: [URL]
    ) throws {
        try PathCreation.directories(
            at: urls
        )
    }
}
