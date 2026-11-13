import Foundation
import Readers

/// User settings of an Agentic home. Read from the home's `config.json`
/// until `.frame` replaces it as the configuration language; every field is
/// optional on disk and falls back to its default.
public struct AgenticSettings: Sendable, Codable, Hashable {
    public var log: Log
    public var mutations: Mutations

    public init(
        log: Log = .init(),
        mutations: Mutations = .init()
    ) {
        self.log = log
        self.mutations = mutations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.log = try container.decodeIfPresent(Log.self, forKey: .log) ?? .init()
        self.mutations = try container.decodeIfPresent(Mutations.self, forKey: .mutations) ?? .init()
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

public extension AgenticSettings {
    /// When coordinated file mutations reach the disk.
    struct Mutations: Sendable, Codable, Hashable {
        public enum Publication: String, Sendable, Codable, Hashable, CaseIterable {
            /// The root agent's mutations publish once approved; delegated
            /// workers' changes wait for one combined review at run end.
            case approval
            /// Every mutation stays staged until the owner reviews and
            /// publishes it.
            case review
        }

        public var publication: Publication

        public init(
            publication: Publication = .approval
        ) {
            self.publication = publication
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.publication = try container.decodeIfPresent(
                Publication.self,
                forKey: .publication
            ) ?? .approval
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
