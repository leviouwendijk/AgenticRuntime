import Foundation
import Frame
import Readers

/// User settings of an Agentic home, the `settings` binding of the home's
/// `settings.frame`:
///
///     import agentic;
///     let notes: PathScope = .{ .path = "~/notes/**" };
///     let settings: AgenticSettings = .{
///         .paths = .{ .ask = [notes] },
///         .mutations = .{ .publication = .review },
///     };
///
/// Every field is optional and falls back to its default; an unknown field
/// is an error.
public struct AgenticSettings: Sendable, Codable, Hashable {
    public var log: Log
    public var mutations: Mutations
    public var paths: Paths

    public init(
        log: Log = .init(),
        mutations: Mutations = .init(),
        paths: Paths = .init()
    ) {
        self.log = log
        self.mutations = mutations
        self.paths = paths
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.log = try container.decodeIfPresent(Log.self, forKey: .log) ?? .init()
        self.mutations = try container.decodeIfPresent(Mutations.self, forKey: .mutations) ?? .init()
        self.paths = try container.decodeIfPresent(Paths.self, forKey: .paths) ?? .init()
    }
}

public extension AgenticSettings {
    /// Paths outside the workspace, by how they are treated. Parsed and
    /// checked; not yet applied at session start.
    struct Paths: Sendable, Codable, Hashable {
        public var allow: [PathScope]
        public var ask: [PathScope]
        public var deny: [PathScope]

        public init(
            allow: [PathScope] = [],
            ask: [PathScope] = [],
            deny: [PathScope] = []
        ) {
            self.allow = allow
            self.ask = ask
            self.deny = deny
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.allow = try container.decodeIfPresent([PathScope].self, forKey: .allow) ?? []
            self.ask = try container.decodeIfPresent([PathScope].self, forKey: .ask) ?? []
            self.deny = try container.decodeIfPresent([PathScope].self, forKey: .deny) ?? []
        }
    }
}

/// A path, a directory with everything below it (`dir/**`) or a single
/// file, and which sessions it is for.
public struct PathScope: Sendable, Codable, Hashable {
    public enum Sessions: String, Sendable, Codable, Hashable {
        case all
    }

    public var path: String
    public var sessions: Sessions
    /// Only list, read and scan.
    public var readOnly: Bool

    public init(
        path: String,
        sessions: Sessions = .all,
        readOnly: Bool = false
    ) {
        self.path = path
        self.sessions = sessions
        self.readOnly = readOnly
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.sessions = try container.decodeIfPresent(Sessions.self, forKey: .sessions) ?? .all
        self.readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
    }

    /// The directory or file the scope names: `dir/**` is `dir`, `~` the
    /// home directory. Other wildcards are not supported yet.
    public func resolvedPath() throws -> String {
        var path = self.path
        if path.hasSuffix("/**") { path.removeLast(3) }
        guard !path.contains(where: { "*?[{".contains($0) }) else {
            throw AgenticSettingsError.unsupported_pattern(self.path)
        }
        return (path as NSString).expandingTildeInPath
    }
}

/// The `agentic` Frame module: what `import agentic;` makes nameable.
public enum AgenticFrame {
    public static let module = Frame.Module("agentic", types: [
        .decodable(AgenticSettings.self, named: "AgenticSettings"),
        .decodable(PathScope.self, named: "PathScope"),
    ])

    public static let environment = Frame.Environment([module])
}

public enum AgenticSettingsError: Error, Sendable, Hashable, LocalizedError {
    case unsupported_pattern(String)
    case invalid(file: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .unsupported_pattern(let path):
            return "'\(path)': only a path or dir/** is supported in a PathScope."
        case .invalid(let file, let message):
            return "\(file): \(message)"
        }
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
    /// The home's settings; defaults when `settings.frame` is absent or
    /// declares no `settings`.
    func settings() throws -> AgenticSettings {
        guard let document = try settingsDocument(),
              document.binding(named: "settings") != nil
        else {
            return .init()
        }
        return try readingSettings {
            try document.decode(AgenticSettings.self, binding: "settings")
        }
    }

    /// Every `let name: PathScope` in `settings.frame`, by name.
    func pathScopes() throws -> [String: PathScope] {
        guard let document = try settingsDocument() else { return [:] }
        return try readingSettings {
            try Dictionary(
                document.bindings(ofType: "PathScope").map {
                    ($0.name, try document.decode(PathScope.self, binding: $0.name))
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    private func settingsDocument() throws -> Frame.Document? {
        let read = try DataFileReader(layout.settingsfile).read(
            options: .init(missingFilePolicy: .returnEmpty)
        )
        guard !read.data.isEmpty else {
            return nil
        }
        return try readingSettings {
            try Frame.parse(
                String(decoding: read.data, as: UTF8.self),
                filePath: layout.settingsfile.path,
                environment: AgenticFrame.environment
            )
        }
    }

    private func readingSettings<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as AgenticSettingsError {
            throw error
        } catch {
            throw AgenticSettingsError.invalid(
                file: layout.settingsfile.path,
                message: String(describing: error)
            )
        }
    }
}
