import Foundation

public actor FileApprovalEventStore: AgentApprovalEventStore {
    public let fileURL: URL

    public init(
        fileURL: URL
    ) {
        self.fileURL = fileURL.standardizedFileURL
    }

    public func loadEvents() async throws -> [AgentApprovalEvent] {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return []
        }

        let data = try Data(
            contentsOf: fileURL
        )

        guard !data.isEmpty else {
            return []
        }

        if let events = try? JSONDecoder().decode(
            [AgentApprovalEvent].self,
            from: data
        ) {
            return events
        }

        guard let text = String(
            data: data,
            encoding: .utf8
        ) else {
            return []
        }

        return try text
            .split(
                separator: "\n",
                omittingEmptySubsequences: true
            )
            .map { line in
                try JSONDecoder().decode(
                    AgentApprovalEvent.self,
                    from: Data(line.utf8)
                )
            }
    }

    public func append(
        _ event: AgentApprovalEvent
    ) async throws {
        try ensureParentDirectoryExists()

        let data = try JSONEncoder().encode(
            event
        )

        if !FileManager.default.fileExists(
            atPath: fileURL.path
        ) {
            try data.write(
                to: fileURL,
                options: .atomic
            )
            try appendNewline()
            return
        }

        let handle = try FileHandle(
            forWritingTo: fileURL
        )

        defer {
            try? handle.close()
        }

        try handle.seekToEnd()

        if try needsLeadingNewline() {
            try handle.write(
                contentsOf: Data("\n".utf8)
            )
        }

        try handle.write(
            contentsOf: data
        )
        try handle.write(
            contentsOf: Data("\n".utf8)
        )
    }
}

private extension FileApprovalEventStore {
    func ensureParentDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func appendNewline() throws {
        let handle = try FileHandle(
            forWritingTo: fileURL
        )

        defer {
            try? handle.close()
        }

        try handle.seekToEnd()
        try handle.write(
            contentsOf: Data("\n".utf8)
        )
    }

    func needsLeadingNewline() throws -> Bool {
        let data = try Data(
            contentsOf: fileURL
        )

        guard let last = data.last else {
            return false
        }

        return last != Character("\n").asciiValue
    }
}
