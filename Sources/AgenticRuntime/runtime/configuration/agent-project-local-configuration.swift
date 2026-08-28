import Foundation

public struct AgentProjectLocalConfiguration: Sendable, Codable, Hashable {
    public var version: Int
    public var sessionStorageMode: SessionStorageMode?
    public var customSessionRoot: String?
    public var customTranscriptRoot: String?
    public var metadata: [String: String]

    public init(
        version: Int = 1,
        sessionStorageMode: SessionStorageMode? = nil,
        customSessionRoot: String? = nil,
        customTranscriptRoot: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.version = version
        self.sessionStorageMode = sessionStorageMode
        self.customSessionRoot = customSessionRoot
        self.customTranscriptRoot = customTranscriptRoot
        self.metadata = metadata
    }

    public static func load(
        from url: URL
    ) throws -> Self {
        let data = try Data(
            contentsOf: url
        )

        return try JSONDecoder().decode(
            Self.self,
            from: data
        )
    }

    public func write(
        to url: URL
    ) throws {
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
            self
        )

        try data.write(
            to: url,
            options: .atomic
        )
    }
}

public extension AgentProjectLocalConfiguration {
    init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.version = try container.decodeIfPresent(
            Int.self,
            forKey: .version
        ) ?? 1
        self.sessionStorageMode = try container.decodeIfPresent(
            SessionStorageMode.self,
            forKey: .sessionStorageMode
        )
        self.customSessionRoot = try container.decodeIfPresent(
            String.self,
            forKey: .customSessionRoot
        )
        self.customTranscriptRoot = try container.decodeIfPresent(
            String.self,
            forKey: .customTranscriptRoot
        )
        self.metadata = try container.decodeIfPresent(
            [String: String].self,
            forKey: .metadata
        ) ?? [:]
    }
}
