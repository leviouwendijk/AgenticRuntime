import Foundation
import Readers

/// User settings of an Agentic home. Read from the home's `config.json`
/// until `.frame` replaces it as the configuration language; every field is
/// optional on disk and falls back to its default.
public struct AgenticSettings: Sendable, Codable, Hashable {
    public var log: Log

    public init(
        log: Log = .init()
    ) {
        self.log = log
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.log = try container.decodeIfPresent(Log.self, forKey: .log) ?? .init()
    }
}

public extension AgenticSettings {
    /// How session logs are written. See `Run.Log.Durability`.
    struct Log: Sendable, Codable, Hashable {
        public var durability: Run.Log.Durability

        public init(
            durability: Run.Log.Durability = .entry
        ) {
            self.durability = durability
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.durability = try container.decodeIfPresent(
                Run.Log.Durability.self,
                forKey: .durability
            ) ?? .entry
        }
    }
}

public extension AgentHome {
    /// The home's settings; defaults when no configuration file exists.
    func settings() throws -> AgenticSettings {
        let read = try DataFileReader(layout.configfile).read(
            options: .init(missingFilePolicy: .returnEmpty)
        )
        guard !read.data.isEmpty else {
            return .init()
        }
        return try JSONDecoder().decode(
            AgenticSettings.self,
            from: read.data
        )
    }
}
