import Agentic
import Foundation
import IO
import Primitives
import Readers

public extension Run.Log {
    /// Where session logs live, how they are written, and how they are read
    /// back. Logs sit in the storage layout's session directories:
    /// `sessions/<id>/log.jsonl` and `sessions/<id>/payloads/<digest>.json`.
    struct Store: Sendable {
        public let storage: AgentRuntimeStorageLayout
        public let durability: Durability

        public init(
            storage: AgentRuntimeStorageLayout,
            durability: Durability = .entry
        ) {
            self.storage = storage
            self.durability = durability
        }

        /// Logs under an Agentic home, written as its settings say.
        public static func home(
            _ home: AgentHome
        ) throws -> Self {
            .init(
                storage: home.layout.runtimeStorage,
                durability: try home.settings().log.durability
            )
        }

        public func open(
            session: String,
            metadata: [String: String] = [:]
        ) throws -> Run.Log {
            try .init(
                session: session,
                file: storage.logfile(sessionID: session),
                payloads: storage.payloadsdir(sessionID: session),
                durability: durability,
                metadata: metadata
            )
        }
    }

    /// A log as read from disk.
    struct Contents: Sendable, Hashable {
        public let header: Header
        public let entries: [Entry]
    }

    struct Summary: Sendable, Hashable {
        public let session: String
        public let header: Header
        public let lastActivity: Date
        public let steps: Int
        /// The first user message, if any.
        public let firstPrompt: String?
    }
}

public extension Run.Log.Store {
    func read(
        session: String
    ) throws -> Run.Log.Contents {
        try Run.Log.read(file: storage.logfile(sessionID: session))
    }

    func payload<Value: Decodable>(
        _ digest: Run.Log.Digest,
        as type: Value.Type,
        session: String
    ) throws -> Value {
        try Run.Log.payload(digest, as: type, in: storage.payloadsdir(sessionID: session))
    }

    /// The exact request a `request` entry recorded.
    func request(
        _ entry: Run.Log.Entry.Request,
        session: String
    ) throws -> AgentRequest {
        try Run.Log.request(entry, in: storage.payloadsdir(sessionID: session))
    }

    func detail(
        of entry: Run.Log.Entry,
        session: String
    ) throws -> JSONValue {
        try Run.Log.detail(of: entry, in: storage.payloadsdir(sessionID: session))
    }

    /// One line per session for choosing among them, most recent first.
    func summaries() throws -> [Run.Log.Summary] {
        try sessions().compactMap { session in
            guard let contents = try? read(session: session) else { return nil }
            let firstPrompt = contents.entries.lazy.compactMap { entry -> String? in
                guard case .message(let stored) = entry.body,
                      let message = try? payload(stored.digest, as: Message.self, session: session),
                      message.role == .user
                else { return nil }
                return message.content.blocks.lazy.compactMap { block -> String? in
                    if case .text(let text) = block { return text }
                    return nil
                }.first
            }.first
            return .init(
                session: session,
                header: contents.header,
                lastActivity: contents.entries.last?.time ?? contents.header.created,
                steps: contents.entries.count,
                firstPrompt: firstPrompt
            )
        }
    }

    /// A session by ID, unique ID prefix, or `latest`.
    func resolve(
        _ reference: String
    ) throws -> String {
        let sessions = try sessions()
        if reference == "latest", let latest = sessions.first {
            return latest
        }
        if sessions.contains(reference) {
            return reference
        }
        let matches = sessions.filter { $0.lowercased().hasPrefix(reference.lowercased()) }
        guard matches.count == 1, let match = matches.first else {
            throw Run.Log.Failure.unknownSession(reference, candidates: matches.count)
        }
        return match
    }

    /// Sessions that have a log, most recently written first.
    func sessions() throws -> [String] {
        guard FileSystem.default.exists(storage.sessionsdir) else {
            return []
        }
        return try FileSystem.default.directory.contents(storage.sessionsdir)
            .compactMap { dir -> (String, Date)? in
                let session = dir.lastPathComponent
                let metadata = try FileInspector(storage.logfile(sessionID: session)).inspect()
                guard metadata.existed else {
                    return nil
                }
                return (session, metadata.modifiedAt ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

/// Reading this session's own log. Staged entries are written first, so a
/// reader always sees every step recorded so far.
public extension Run.Log {
    func read() throws -> Contents {
        try flush()
        return try Self.read(file: file)
    }

    nonisolated func payload<Value: Decodable>(
        _ digest: Digest,
        as type: Value.Type
    ) throws -> Value {
        try Self.payload(digest, as: type, in: payloads)
    }

    nonisolated func request(
        _ entry: Entry.Request
    ) throws -> AgentRequest {
        try Self.request(entry, in: payloads)
    }

    nonisolated func detail(
        of entry: Entry
    ) throws -> JSONValue {
        try Self.detail(of: entry, in: payloads)
    }

    /// The full response recorded for a call, the latest if it was
    /// answered more than once.
    func response(
        call: String
    ) throws -> FunctionCall.Response? {
        for entry in try read().entries.reversed() {
            guard case .response(let response) = entry.body,
                  response.call.id == call else {
                continue
            }
            return try payload(response.digest, as: FunctionCall.Response.self)
        }
        return nil
    }
}

extension Run.Log {
    static func read(
        file: URL
    ) throws -> Contents {
        let data = try DataFileReader(file).read().data
        guard let first = data.split(separator: 0x0A).first else {
            throw Failure.missingHeader(file)
        }
        let header = try decoder.decode(Header.self, from: Data(first))
        guard header.version == version else {
            throw Failure.unsupportedVersion(header.version)
        }
        return .init(
            header: header,
            entries: try entries(in: data)
        )
    }

    static func payload<Value: Decodable>(
        _ digest: Digest,
        as type: Value.Type,
        in payloads: URL
    ) throws -> Value {
        try decoder.decode(
            type,
            from: DataFileReader(payload(digest, in: payloads)).read().data
        )
    }

    static func request(
        _ entry: Entry.Request,
        in payloads: URL
    ) throws -> AgentRequest {
        var request = try payload(entry.options, as: AgentRequest.self, in: payloads)
        request.messages = try entry.messages.map {
            try payload($0, as: Message.self, in: payloads)
        }
        request.tools = try payload(entry.tools, as: [ToolDescriptor].self, in: payloads)
        return request
    }

    /// The entry with its stored bodies filled in. A request lists its
    /// messages by id, role and digest rather than inlining the history.
    static func detail(
        of entry: Entry,
        in payloads: URL
    ) throws -> JSONValue {
        switch entry.body {
        case .state(let state):
            return try .encoding(state)
        case .observation(let observation):
            return try .encoding(observation)
        case .branch(let event):
            return try .encoding(event)
        case .message(let stored):
            return try payload(stored.digest, as: JSONValue.self, in: payloads)
        case .response(let response):
            return try payload(response.digest, as: JSONValue.self, in: payloads)
        case .call(let call):
            return .object([
                "call": try .encoding(call.call),
                "input": try payload(call.input, as: JSONValue.self, in: payloads),
            ])
        case .request(let request):
            let messages = try request.messages.map { digest in
                let message = try payload(digest, as: Message.self, in: payloads)
                return JSONValue.object([
                    "id": .string(message.id),
                    "role": .string(message.role.rawValue),
                    "digest": .string(digest.rawValue),
                ])
            }
            let tools = try payload(request.tools, as: [ToolDescriptor].self, in: payloads)
            return .object([
                "usage": try .encoding(request.usage),
                "messages": .array(messages),
                "tools": .array(tools.map { .string($0.identifier.rawValue) }),
            ])
        }
    }
}
