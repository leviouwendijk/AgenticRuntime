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
        let file = storage.logfile(sessionID: session)
        let data = try DataFileReader(file).read().data
        guard let first = data.split(separator: 0x0A).first else {
            throw Run.Log.Failure.missingHeader(file)
        }
        let header = try Run.Log.decoder.decode(Run.Log.Header.self, from: Data(first))
        guard header.version == Run.Log.version else {
            throw Run.Log.Failure.unsupportedVersion(header.version)
        }
        return .init(
            header: header,
            entries: try Run.Log.entries(in: data)
        )
    }

    func payload<Value: Decodable>(
        _ digest: Run.Log.Digest,
        as type: Value.Type,
        session: String
    ) throws -> Value {
        let url = Run.Log.payload(digest, in: storage.payloadsdir(sessionID: session))
        return try Run.Log.decoder.decode(type, from: DataFileReader(url).read().data)
    }

    /// The exact request a `request` entry recorded.
    func request(
        _ entry: Run.Log.Entry.Request,
        session: String
    ) throws -> AgentRequest {
        var request = try payload(entry.options, as: AgentRequest.self, session: session)
        request.messages = try entry.messages.map {
            try payload($0, as: Message.self, session: session)
        }
        request.tools = try payload(entry.tools, as: [ToolDescriptor].self, session: session)
        return request
    }
}
