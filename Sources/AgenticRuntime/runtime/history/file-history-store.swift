import Foundation

public actor FileHistoryStore: AgentHistoryStore {
    public let sessionsdir: URL

    public init(
        sessionsdir: URL
    ) {
        self.sessionsdir = sessionsdir.standardizedFileURL
    }

    public func loadCheckpoint(
        sessionID: String
    ) async throws -> AgentHistoryCheckpoint? {
        let url = checkpointURL(
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
            AgentHistoryCheckpoint.self,
            from: data
        )
    }

    public func saveCheckpoint(
        _ checkpoint: AgentHistoryCheckpoint
    ) async throws {
        let url = checkpointURL(
            for: checkpoint.id
        )

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(
            checkpoint
        )

        try data.write(
            to: url,
            options: .atomic
        )
    }

    public func deleteCheckpoint(
        sessionID: String
    ) async throws {
        let url = checkpointURL(
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

private extension FileHistoryStore {
    func checkpointURL(
        for sessionID: String
    ) -> URL {
        sessionsdir
            .appendingPathComponent(
                sessionID,
                isDirectory: true
            )
            .appendingPathComponent(
                "checkpoint.json",
                isDirectory: false
            )
    }
}
