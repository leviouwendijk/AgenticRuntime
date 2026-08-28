import Foundation

public struct AgentProjectConfiguration: Sendable, Codable, Hashable {
    public var version: Int
    public var projectID: String?
    public var name: String?
    public var defaultProfileID: String?
    public var defaultModel: String?
    public var defaultSessionStorageMode: SessionStorageMode?
    public var workspaceRoot: String?
    public var sharedSkills: [String]
    public var metadata: [String: String]

    public init(
        version: Int = 1,
        projectID: String? = nil,
        name: String? = nil,
        defaultProfileID: String? = nil,
        defaultModel: String? = nil,
        defaultSessionStorageMode: SessionStorageMode? = nil,
        workspaceRoot: String? = nil,
        sharedSkills: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.version = version
        self.projectID = projectID
        self.name = name
        self.defaultProfileID = defaultProfileID
        self.defaultModel = defaultModel
        self.defaultSessionStorageMode = defaultSessionStorageMode
        self.workspaceRoot = workspaceRoot
        self.sharedSkills = sharedSkills
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

public extension AgentProjectConfiguration {
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
        self.projectID = try container.decodeIfPresent(
            String.self,
            forKey: .projectID
        )
        self.name = try container.decodeIfPresent(
            String.self,
            forKey: .name
        )
        self.defaultProfileID = try container.decodeIfPresent(
            String.self,
            forKey: .defaultProfileID
        )
        self.defaultModel = try container.decodeIfPresent(
            String.self,
            forKey: .defaultModel
        )
        self.defaultSessionStorageMode = try container.decodeIfPresent(
            SessionStorageMode.self,
            forKey: .defaultSessionStorageMode
        )
        self.workspaceRoot = try container.decodeIfPresent(
            String.self,
            forKey: .workspaceRoot
        )
        self.sharedSkills = try container.decodeIfPresent(
            [String].self,
            forKey: .sharedSkills
        ) ?? []
        self.metadata = try container.decodeIfPresent(
            [String: String].self,
            forKey: .metadata
        ) ?? [:]
    }
}
