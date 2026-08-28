import Agentic
import Foundation

public actor FileAgentArtifactStore: AgentArtifactStore {
    public let sessionID: String
    public let artifactdir: URL

    public init(
        sessionID: String,
        artifactdir: URL
    ) {
        self.sessionID = sessionID
        self.artifactdir = artifactdir.standardizedFileURL
    }

    public func emit(
        _ draft: AgentArtifactDraft
    ) async throws -> AgentArtifactRecord {
        let content = draft.content

        guard !content.isEmpty else {
            throw AgentArtifactError.emptyContent
        }

        let id = UUID().uuidString
        let contentData = Data(content.utf8)
        let filename = normalizedFilename(
            draft.filename,
            kind: draft.kind
        )
        let contentType = normalizedContentType(
            draft.contentType,
            kind: draft.kind
        )

        let artifact = AgentArtifact(
            id: id,
            sessionID: sessionID,
            kind: draft.kind,
            title: normalizedTitle(
                draft.title
            ),
            filename: filename,
            contentType: contentType,
            byteCount: contentData.count,
            metadata: draft.metadata
        )

        let artifactdir = artifactDirectoryURL(
            id: id
        )

        try FileManager.default.createDirectory(
            at: artifactdir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        try contentData.write(
            to: contentURL(
                for: artifact
            ),
            options: .atomic
        )

        let metadataData = try metadataEncoder.encode(
            artifact
        )

        try metadataData.write(
            to: metadataURL(
                id: id
            ),
            options: .atomic
        )

        return .init(
            artifact: artifact,
            content: content
        )
    }

    public func list(
        kinds: [AgentArtifactKind] = [],
        latestFirst: Bool = true,
        limit: Int? = nil
    ) async throws -> [AgentArtifact] {
        guard FileManager.default.fileExists(
            atPath: artifactdir.path
        ) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: artifactdir,
            includingPropertiesForKeys: nil,
            options: [
                .skipsHiddenFiles
            ]
        )

        var artifacts = try urls.compactMap { url -> AgentArtifact? in
            var isDirectory: ObjCBool = false

            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                return nil
            }

            let metadataURL = url.appendingPathComponent(
                "artifact.json",
                isDirectory: false
            )

            guard FileManager.default.fileExists(
                atPath: metadataURL.path
            ) else {
                return nil
            }

            let data = try Data(
                contentsOf: metadataURL
            )

            guard !data.isEmpty else {
                return nil
            }

            return try JSONDecoder().decode(
                AgentArtifact.self,
                from: data
            )
        }

        if !kinds.isEmpty {
            let allowedKinds = Set(
                kinds
            )

            artifacts = artifacts.filter { artifact in
                allowedKinds.contains(
                    artifact.kind
                )
            }
        }

        artifacts.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }

            return latestFirst
                ? lhs.createdAt > rhs.createdAt
                : lhs.createdAt < rhs.createdAt
        }

        if let limit {
            return Array(
                artifacts.prefix(
                    max(0, limit)
                )
            )
        }

        return artifacts
    }

    public func load(
        id: String
    ) async throws -> AgentArtifactRecord? {
        let id = normalizedIdentifier(
            id
        )

        let metadataURL = metadataURL(
            id: id
        )

        guard FileManager.default.fileExists(
            atPath: metadataURL.path
        ) else {
            return nil
        }

        let metadataData = try Data(
            contentsOf: metadataURL
        )

        guard !metadataData.isEmpty else {
            return nil
        }

        let artifact = try JSONDecoder().decode(
            AgentArtifact.self,
            from: metadataData
        )

        let contentData = try Data(
            contentsOf: contentURL(
                for: artifact
            )
        )

        guard let content = String(
            data: contentData,
            encoding: .utf8
        ) else {
            throw AgentArtifactError.unreadableContent(
                artifact.id
            )
        }

        return .init(
            artifact: artifact,
            content: content
        )
    }
}

private extension FileAgentArtifactStore {
    var metadataEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        return encoder
    }

    func artifactDirectoryURL(
        id: String
    ) -> URL {
        artifactdir.appendingPathComponent(
            normalizedIdentifier(
                id
            ),
            isDirectory: true
        )
    }

    func metadataURL(
        id: String
    ) -> URL {
        artifactDirectoryURL(
            id: id
        ).appendingPathComponent(
            "artifact.json",
            isDirectory: false
        )
    }

    func contentURL(
        for artifact: AgentArtifact
    ) -> URL {
        artifactDirectoryURL(
            id: artifact.id
        ).appendingPathComponent(
            artifact.filename,
            isDirectory: false
        )
    }

    func normalizedIdentifier(
        _ value: String
    ) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return safeFileComponent(
            trimmed
        )
    }

    func normalizedTitle(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizedContentType(
        _ value: String?,
        kind: AgentArtifactKind
    ) -> String {
        guard let value else {
            return kind.defaultContentType
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? kind.defaultContentType : trimmed
    }

    func normalizedFilename(
        _ value: String?,
        kind: AgentArtifactKind
    ) -> String {
        let fallback = "artifact.\(kind.defaultFileExtension)"

        guard let value else {
            return fallback
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            return fallback
        }

        let sanitized = safeFilename(
            trimmed
        )

        return sanitized.isEmpty ? fallback : sanitized
    }

    func safeFilename(
        _ value: String
    ) -> String {
        let filename = value
            .replacingOccurrences(
                of: "/",
                with: "-"
            )
            .replacingOccurrences(
                of: "\\",
                with: "-"
            )

        return safeFileComponent(
            filename
        )
    }

    func safeFileComponent(
        _ value: String
    ) -> String {
        value.map { character in
            if character.isLetter
                || character.isNumber
                || character == "-"
                || character == "_"
                || character == "." {
                return String(
                    character
                )
            }

            return "-"
        }.joined()
    }
}
