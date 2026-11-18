import Foundation
import Frame
import Path
import Readers
import Version

/// User settings of an Agentic home, the `settings` binding of the home's
/// `settings.frame`:
///
///     import Agentic;
///     let notes: PathScope = .{ .path = "~/notes/**" };
///     let settings: AgenticSettings = .{
///         .schema = .{ .major = 1, .minor = 0, .patch = 0 },
///         .paths = .{ .ask = [notes], .symlinks = .roots },
///         .mutations = .{ .publication = .review },
///         .exports = .{ .directory = "~/exports" },
///     };
///
/// Every field is optional and falls back to its default; an unknown field
/// is an error.
public struct AgenticSettings: Sendable, Codable, Hashable {
    /// The settings schema this program reads. A minor or patch raise only
    /// adds; a major raise changes what an existing field means.
    public static let schemaVersion = SemanticVersion(major: 1, minor: 0, patch: 0)

    /// The schema the file was written for; nil when it declares none.
    public var schema: SemanticVersion?
    public var exports: Exports
    public var log: Log
    public var mutations: Mutations
    public var paths: Paths

    public init(
        schema: SemanticVersion? = nil,
        exports: Exports = .init(),
        log: Log = .init(),
        mutations: Mutations = .init(),
        paths: Paths = .init()
    ) {
        self.schema = schema
        self.exports = exports
        self.log = log
        self.mutations = mutations
        self.paths = paths
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = try container.decodeIfPresent(SemanticVersion.self, forKey: .schema)
        self.exports = try container.decodeIfPresent(Exports.self, forKey: .exports) ?? .init()
        self.log = try container.decodeIfPresent(Log.self, forKey: .log) ?? .init()
        self.mutations = try container.decodeIfPresent(Mutations.self, forKey: .mutations) ?? .init()
        self.paths = try container.decodeIfPresent(Paths.self, forKey: .paths) ?? .init()
    }
}

public extension AgenticSettings {
    /// Paths outside the workspace, by how they are treated, and which
    /// symlinks a path may pass through. Applied at session start.
    struct Paths: Sendable, Codable, Hashable {
        public var allow: [PathScope]
        public var ask: [PathScope]
        public var deny: [PathScope]
        /// `.never`: no path through a symlink. `.roots` (default): a
        /// symlink is followed when it leads into one of the session's
        /// roots, and checked there. `.anywhere`: not checked.
        public var symlinks: PathSymlinkPolicy

        public init(
            allow: [PathScope] = [],
            ask: [PathScope] = [],
            deny: [PathScope] = [],
            symlinks: PathSymlinkPolicy = .roots
        ) {
            self.allow = allow
            self.ask = ask
            self.deny = deny
            self.symlinks = symlinks
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.allow = try container.decodeIfPresent([PathScope].self, forKey: .allow) ?? []
            self.ask = try container.decodeIfPresent([PathScope].self, forKey: .ask) ?? []
            self.deny = try container.decodeIfPresent([PathScope].self, forKey: .deny) ?? []
            self.symlinks = try container.decodeIfPresent(PathSymlinkPolicy.self, forKey: .symlinks) ?? .roots
        }
    }
}

/// A path, a directory with everything below it (`dir/**`) or a single
/// file, and which sessions it is for.
public struct PathScope: Sendable, Codable, Hashable {
    public enum Sessions: String, Sendable, Codable, Hashable, CaseIterable {
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

/// The `agentic` Frame module: what `import Agentic;` makes nameable.
public enum FrameAgenticModule {
    public static let module = Frame.Module("Agentic", types: [
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
    /// Where results the owner exports (`:export`) are written.
    struct Exports: Sendable, Codable, Hashable {
        public static let defaultDirectory = ".agentic/artifacts/exports"

        /// Absolute, `~`-relative, or relative to the workspace. Defaults
        /// to `.agentic/artifacts/exports`: beside the runtime's per-session
        /// artifact directories, never one of them.
        public var directory: String

        public init(
            directory: String = Exports.defaultDirectory
        ) {
            self.directory = directory
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.directory = try container.decodeIfPresent(
                String.self,
                forKey: .directory
            ) ?? Exports.defaultDirectory
        }

        /// `directory` against `workspace`.
        public func resolvedDirectory(workspace: String) -> URL {
            let expanded = (directory as NSString).expandingTildeInPath
            return expanded.hasPrefix("/")
                ? URL(fileURLWithPath: expanded, isDirectory: true)
                : URL(fileURLWithPath: workspace, isDirectory: true)
                    .appendingPathComponent(expanded, isDirectory: true)
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
            /// The root agent's mutations publish once approved; workers
            /// follow `workers`.
            case approval
            /// Every mutation stays staged until the owner reviews and
            /// publishes it.
            case review
        }

        /// What a delegated worker's admitted change does.
        public enum Workers: String, Sendable, Codable, Hashable, CaseIterable {
            /// Written within the worker's scope as soon as it is admitted,
            /// so the worker can build and test it; reviewed afterwards
            /// (keep or roll back) with the rest of the unreviewed changes.
            case publish
            /// Staged off disk until the owner reviews and publishes it.
            case stage
        }

        public var publication: Publication
        public var workers: Workers

        public init(
            publication: Publication = .approval,
            workers: Workers = .publish
        ) {
            self.publication = publication
            self.workers = workers
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.publication = try container.decodeIfPresent(
                Publication.self,
                forKey: .publication
            ) ?? .approval
            self.workers = try container.decodeIfPresent(
                Workers.self,
                forKey: .workers
            ) ?? .publish
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
                environment: FrameAgenticModule.environment
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

public extension AgentHome {
    /// A domain's configuration document, `domains/<fileName>`, parsed
    /// against the domain's own Frame environment; `nil` when the file is
    /// absent. Agentic knows no domain's types: the domain supplies them.
    func domainDocument(
        _ fileName: String,
        environment: Frame.Environment
    ) throws -> Frame.Document? {
        let file = layout.domainfile(fileName)
        let read = try DataFileReader(file).read(
            options: .init(missingFilePolicy: .returnEmpty)
        )
        guard !read.data.isEmpty else {
            return nil
        }
        do {
            return try Frame.parse(
                String(decoding: read.data, as: UTF8.self),
                filePath: file.path,
                environment: environment
            )
        } catch {
            throw AgenticSettingsError.invalid(
                file: file.path,
                message: String(describing: error)
            )
        }
    }
}
