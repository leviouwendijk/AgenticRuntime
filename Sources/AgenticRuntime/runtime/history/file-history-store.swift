import Foundation
import IO
import Readers

/// A recovery snapshot per session: the state a run resumes from. The
/// complete step record is the session log (`Run.Log`), not this file.
public actor FileHistoryStore: AgentHistoryStore {
    public let sessionsdir: URL

    public init(
        sessionsdir: URL
    ) {
        self.sessionsdir = sessionsdir.standardizedFileURL
    }

    public func loadCheckpoint(
        sessionID: String
    ) async throws -> AgentExecutor.Checkpoint? {
        let data = try DataFileReader(checkpointURL(for: sessionID)).read(
            options: .init(missingFilePolicy: .returnEmpty)
        ).data

        guard !data.isEmpty else {
            return nil
        }

        return try JSONDecoder().decode(
            AgentExecutor.Checkpoint.self,
            from: data
        )
    }

    /// Written beside its final name and moved into place, so a reader sees
    /// either the previous snapshot or the new one, never a partial file.
    public func saveCheckpoint(
        _ checkpoint: AgentExecutor.Checkpoint
    ) async throws {
        let url = checkpointURL(
            for: checkpoint.id
        )
        let partial = url.appendingPathExtension("partial")

        try FileSystem.default.directory.create(url.deletingLastPathComponent())

        var destination = Destination(
            try SystemFileDestination(path: partial.path, mode: .truncate)
        )
        try Run.Log.write(
            try JSONEncoder().encode(checkpoint),
            to: &destination
        )
        _ = try destination.flush()

        if FileSystem.default.exists(url) {
            try FileSystem.default.replace(url, with: partial)
        } else {
            try FileSystem.default.move(partial, to: url)
        }
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
