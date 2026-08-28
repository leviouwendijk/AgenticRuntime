import Foundation

public struct FileSessionMetadataStore: AgentSessionMetadataStore {
    public let sessionsdir: URL

    public init(
        sessionsdir: URL
    ) {
        self.sessionsdir = sessionsdir.standardizedFileURL
    }

    public func load(
        sessionID: String
    ) throws -> AgentSessionMetadata? {
        let url = metadataURL(
            for: sessionID
        )

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }

        let data = try Data(
            contentsOf: url
        )

        guard !data.isEmpty else {
            return nil
        }

        return try JSONDecoder().decode(
            AgentSessionMetadata.self,
            from: data
        )
    }

    public func save(
        _ metadata: AgentSessionMetadata
    ) throws {
        let url = metadataURL(
            for: metadata.sessionID
        )

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        let data = try encoder.encode(
            metadata.touching()
        )

        try data.write(
            to: url,
            options: .atomic
        )
    }

    public func delete(
        sessionID: String
    ) throws {
        let url = metadataURL(
            for: sessionID
        )

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return
        }

        try FileManager.default.removeItem(
            at: url
        )
    }
}

private extension FileSessionMetadataStore {
    func metadataURL(
        for sessionID: String
    ) -> URL {
        sessionsdir
            .appendingPathComponent(
                sessionID,
                isDirectory: true
            )
            .appendingPathComponent(
                "state.json",
                isDirectory: false
            )
    }
}
