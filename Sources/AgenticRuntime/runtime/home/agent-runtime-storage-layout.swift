import Foundation
import Path

public struct AgentRuntimeStorageLayout: Sendable, Codable, Hashable {
    public let root: URL
    public let schema: AgentRuntimeStorageTreeSchema

    public init(
        root: URL,
        schema: AgentRuntimeStorageTreeSchema = .init()
    ) {
        self.root = root.standardizedFileURL
        self.schema = schema
    }

    public var sessionsdir: URL {
        directoryURL(for: schema.sessionsdir)
    }

    public var transcriptsdir: URL {
        directoryURL(for: schema.transcriptsdir)
    }

    public var approvalsdir: URL {
        directoryURL(for: schema.approvalsdir)
    }

    public var tasksdir: URL {
        directoryURL(for: schema.tasksdir)
    }

    public var artifactsdir: URL {
        directoryURL(for: schema.artifactsdir)
    }

    public var preparedintentsdir: URL {
        directoryURL(for: schema.preparedintentsdir)
    }

    public var cachedir: URL {
        directoryURL(for: schema.cachedir)
    }

    public var tmpdir: URL {
        directoryURL(for: schema.tmpdir)
    }

    public func sessiondir(
        sessionID: String
    ) -> URL {
        directoryURL(
            for: schema.sessiondir(
                sessionID: sessionID
            )
        )
    }

    public func checkpointfile(
        sessionID: String
    ) -> URL {
        fileURL(
            for: schema.checkpointfile(
                sessionID: sessionID
            )
        )
    }

    public func sessionstatefile(
        sessionID: String
    ) -> URL {
        fileURL(
            for: schema.sessionstatefile(
                sessionID: sessionID
            )
        )
    }

    public func transcriptfile(
        sessionID: String
    ) -> URL {
        fileURL(
            for: schema.transcriptfile(
                sessionID: sessionID
            )
        )
    }

    public func approvalsfile(
        sessionID: String
    ) -> URL {
        fileURL(
            for: schema.approvalsfile(
                sessionID: sessionID
            )
        )
    }

    public func artifactdir(
        sessionID: String
    ) -> URL {
        directoryURL(
            for: schema.artifactdir(
                sessionID: sessionID
            )
        )
    }

    public func createBaseDirectories() throws {
        try createDirectories(
            schema.baseDirectories.map(directoryURL)
        )
    }

    public func createSessionDirectories(
        sessionID: String
    ) throws {
        try createDirectories(
            [
                sessiondir(
                    sessionID: sessionID
                ),
                transcriptsdir,
                approvalsdir,
                artifactdir(
                    sessionID: sessionID
                )
            ]
        )
    }
}

public extension AgentRuntimeStorageLayout {
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

private extension AgentRuntimeStorageLayout {
    func createDirectories(
        _ urls: [URL]
    ) throws {
        try PathCreation.directories(
            at: urls
        )
    }
}
