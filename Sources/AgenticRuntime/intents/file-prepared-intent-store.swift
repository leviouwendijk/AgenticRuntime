// FROZEN: deferred queue (not conversational or ToolPlan execution).
#if AGENTIC_ENABLE_DEFERRED_INTENTS
import Agentic
import IO
import Darwin
import Foundation

/// File-backed intent store. Conditional transitions are serialized across
/// independent processes by an advisory lock on a stable directory lock file.
/// All writers to this store must use this contract (not direct JSON writes).
public actor FilePreparedIntentStore: PreparedIntentStore {
    public let preparedIntentsdir: URL

    public init(preparedIntentsdir: URL) {
        self.preparedIntentsdir = preparedIntentsdir.standardizedFileURL
    }

    public func load(id: PreparedIntentIdentifier) async throws -> PreparedIntent? {
        try read(id: id)
    }

    public func list() async throws -> [PreparedIntent] {
        guard FileSystem.default.exists(preparedIntentsdir) else { return [] }
        let urls = try FileSystem.default.directory.contents(
            preparedIntentsdir,
            options: [.skipsHiddenFiles]
        )
        let intents = try urls.compactMap { url -> PreparedIntent? in
            guard url.pathExtension == "json" else { return nil }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { return nil }
            return try JSONDecoder().decode(PreparedIntent.self, from: data)
        }
        return intents.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func insert(_ intent: PreparedIntent) async throws -> Bool {
        try withExclusiveLock {
            guard try read(id: intent.id) == nil else { return false }
            try write(intent)
            return true
        }
    }

    public func replace(
        _ intent: PreparedIntent,
        matching expected: PreparedIntent
    ) async throws -> Bool {
        guard intent.id == expected.id else { return false }
        return try withExclusiveLock {
            guard try read(id: expected.id) == expected else { return false }
            try write(intent)
            return true
        }
    }

    public func delete(
        id: PreparedIntentIdentifier,
        matching expected: PreparedIntent
    ) async throws -> Bool {
        try withExclusiveLock {
            guard try read(id: id) == expected else { return false }
            try FileSystem.default.remove(intentFileURL(id: id))
            return true
        }
    }
}

private extension FilePreparedIntentStore {
    func read(id: PreparedIntentIdentifier) throws -> PreparedIntent? {
        let url = intentFileURL(id: id)
        guard FileSystem.default.exists(url) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }
        return try JSONDecoder().decode(PreparedIntent.self, from: data)
    }

    func write(_ intent: PreparedIntent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(intent)
        try data.write(to: intentFileURL(id: intent.id), options: .atomic)
    }

    func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        try FileSystem.default.directory.create(preparedIntentsdir)
        let lockURL = preparedIntentsdir.appendingPathComponent(
            ".prepared-intents.lock", isDirectory: false
        )
        let descriptor = lockURL.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            _ = Darwin.flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        guard Darwin.flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return try operation()
    }

    func intentFileURL(id: PreparedIntentIdentifier) -> URL {
        preparedIntentsdir.appendingPathComponent(
            "intent-\(safeFileComponent(id.rawValue)).json",
            isDirectory: false
        )
    }

    func safeFileComponent(_ value: String) -> String {
        value.map { character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return String(character)
            }
            return "_"
        }.joined()
    }
}

#endif // AGENTIC_ENABLE_DEFERRED_INTENTS