import Agentic
import Foundation
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
            session: String
        ) throws -> Run.Log {
            try .init(
                session: session,
                file: storage.logfile(sessionID: session),
                payloads: storage.payloadsdir(sessionID: session),
                durability: durability
            )
        }
    }

    /// A log as read from disk.
    struct Contents: Sendable, Hashable {
        public let header: Header
        public let entries: [Entry]
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
}
