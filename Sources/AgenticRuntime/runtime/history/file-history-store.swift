import Foundation
import IO

public actor FileHistoryStore: AgentHistoryStore {
    public let sessionsdir: URL

    public init(
        sessionsdir: URL
    ) {
        self.sessionsdir = sessionsdir.standardizedFileURL
    }

    public func loadCheckpoint(
        sessionID: String
    ) async throws -> AgentRunner.Checkpoint? {
        let url = checkpointURL(
            for: sessionID
        )

        guard FileSystem.default.exists(url) else {
            return nil
        }

        let data = try Data(
            contentsOf: url
        )

        guard !data.isEmpty else {
            return nil
        }

        return try JSONDecoder().decode(
            AgentRunner.Checkpoint.self,
            from: data
        )
    }

    public func saveCheckpoint(
        _ checkpoint: AgentRunner.Checkpoint
    ) async throws {
        let url = checkpointURL(
            for: checkpoint.id
        )

        try FileSystem.default.directory.create(url.deletingLastPathComponent())

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

        guard FileSystem.default.exists(url) else {
            return
        }

        try FileSystem.default.remove(url)
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
