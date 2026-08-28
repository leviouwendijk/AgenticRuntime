import Agentic
import AgenticExecution
import Foundation

public actor FilePreparedIntentStore: PreparedIntentStore {
    public let preparedIntentsdir: URL

    public init(
        preparedIntentsdir: URL
    ) {
        self.preparedIntentsdir = preparedIntentsdir.standardizedFileURL
    }

    public func load(
        id: PreparedIntentIdentifier
    ) async throws -> PreparedIntent? {
        let url = intentFileURL(
            id: id
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
            PreparedIntent.self,
            from: data
        )
    }

    public func list() async throws -> [PreparedIntent] {
        guard FileManager.default.fileExists(
            atPath: preparedIntentsdir.path
        ) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: preparedIntentsdir,
            includingPropertiesForKeys: nil,
            options: [
                .skipsHiddenFiles
            ]
        )

        let intents = try urls.compactMap { url -> PreparedIntent? in
            guard url.pathExtension == "json" else {
                return nil
            }

            let data = try Data(
                contentsOf: url
            )

            guard !data.isEmpty else {
                return nil
            }

            return try JSONDecoder().decode(
                PreparedIntent.self,
                from: data
            )
        }

        return intents.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func save(
        _ intent: PreparedIntent
    ) async throws {
        try FileManager.default.createDirectory(
            at: preparedIntentsdir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var intent = intent
        intent.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        let data = try encoder.encode(
            intent
        )

        try data.write(
            to: intentFileURL(
                id: intent.id
            ),
            options: .atomic
        )
    }

    public func delete(
        id: PreparedIntentIdentifier
    ) async throws {
        let url = intentFileURL(
            id: id
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

private extension FilePreparedIntentStore {
    func intentFileURL(
        id: PreparedIntentIdentifier
    ) -> URL {
        preparedIntentsdir.appendingPathComponent(
            "intent-\(safeFileComponent(id.rawValue)).json",
            isDirectory: false
        )
    }

    func safeFileComponent(
        _ value: String
    ) -> String {
        value.map { character in
            if character.isLetter
                || character.isNumber
                || character == "-"
                || character == "_" {
                return String(
                    character
                )
            }

            return "_"
        }.joined()
    }
}
