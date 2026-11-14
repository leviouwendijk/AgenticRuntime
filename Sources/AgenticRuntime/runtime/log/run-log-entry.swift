import Agentic
import CryptoKit
import Foundation

public extension Run.Log {
    /// Version of the on-disk record shape. A bump ships with a modernizer
    /// that reads the previous version; lines are never rewritten in place.
    static let version = 1

    /// First line of every log file.
    struct Header: Sendable, Codable, Hashable {
        public let version: Int
        public let session: String
        public let created: Date
        /// What the session ran in: workspace, agent, title, …
        public let metadata: [String: String]

        public init(
            version: Int = Run.Log.version,
            session: String,
            created: Date = Date(),
            metadata: [String: String] = [:]
        ) {
            self.version = version
            self.session = session
            self.created = created
            self.metadata = metadata
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try container.decode(Int.self, forKey: .version)
            self.session = try container.decode(String.self, forKey: .session)
            self.created = try container.decode(Date.self, forKey: .created)
            self.metadata = try container.decodeIfPresent(
                [String: String].self, forKey: .metadata
            ) ?? [:]
        }
    }

    /// How appended entries reach the disk.
    enum Durability: String, Sendable, Codable, Hashable, CaseIterable {
        /// Entries are staged in memory and written at step boundaries. A
        /// crash loses the unwritten tail.
        case buffered
        /// Each entry is written to the file as it is appended. Survives a
        /// crash or kill of the process; the OS decides when it reaches disk.
        case entry
        /// Each entry is written and synchronized to stable storage. Survives
        /// power loss; slowest.
        case synced
    }

    /// Content address of a stored payload: SHA-256 of its canonical JSON.
    /// Equal content is stored once, however often it is recorded.
    struct Digest: RawRepresentable, Sendable, Codable, Hashable, CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        init(_ data: Data) {
            self.rawValue = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }

        public var description: String {
            rawValue
        }
    }

    /// One recorded step. `seq` orders entries within a log; `run` names the
    /// run that produced it, so every run of a session shares one log.
    struct Entry: Sendable, Hashable {
        public let seq: Int
        public let time: Date
        public let run: String?
        public let body: Body

        public init(
            seq: Int,
            time: Date = Date(),
            run: String?,
            body: Body
        ) {
            self.seq = seq
            self.time = time
            self.run = run
            self.body = body
        }
    }
}

public extension Run.Log.Entry {
    typealias Digest = Run.Log.Digest

    enum Body: Sendable, Hashable {
        /// A run event: preflight, approval, denial, skip, suspension,
        /// interruption, failure, compaction, context usage, cost, …
        case state(Run.Event.State)
        /// Live execution evidence, e.g. a command's output.
        case observation(ToolResultObservation)
        /// The exact request sent to the model.
        case request(Request)
        /// A message added to the conversation.
        case message(Stored)
        /// A function call the model made.
        case call(Call)
        /// The response returned for a call.
        case response(Response)
        /// The session was started, resumed or forked.
        case branch(SessionBranchEvent)
    }

    /// A model request, stored message by message so unchanged history is
    /// never stored twice.
    struct Request: Sendable, Codable, Hashable {
        /// Each message's payload, in request order.
        public let messages: [Digest]
        /// The advertised function schemas (`[ToolDescriptor]`).
        public let tools: Digest
        /// The request without messages and tools (`AgentRequest`).
        public let options: Digest
        public let usage: Context.Usage
    }

    struct Stored: Sendable, Codable, Hashable {
        public let id: String
        public let digest: Digest
    }

    struct Call: Sendable, Codable, Hashable {
        public let call: FunctionCall.Reference
        /// The call's input (`JSONValue`).
        public let input: Digest
    }

    struct Response: Sendable, Codable, Hashable {
        public let call: FunctionCall.Reference
        public let isError: Bool
        /// The full response (`FunctionCall.Response`).
        public let digest: Digest
    }
}

/// A line is `{"seq":…,"time":…,"run":…,"<kind>":{…}}`: exactly one body key.
extension Run.Log.Entry: Codable {
    enum CodingKeys: String, CodingKey {
        case seq, time, run
        case state, observation, request, message, call, response, branch
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.seq = try container.decode(Int.self, forKey: .seq)
        self.time = try container.decode(Date.self, forKey: .time)
        self.run = try container.decodeIfPresent(String.self, forKey: .run)

        if let value = try container.decodeIfPresent(Run.Event.State.self, forKey: .state) {
            self.body = .state(value)
        } else if let value = try container.decodeIfPresent(ToolResultObservation.self, forKey: .observation) {
            self.body = .observation(value)
        } else if let value = try container.decodeIfPresent(Request.self, forKey: .request) {
            self.body = .request(value)
        } else if let value = try container.decodeIfPresent(Stored.self, forKey: .message) {
            self.body = .message(value)
        } else if let value = try container.decodeIfPresent(Call.self, forKey: .call) {
            self.body = .call(value)
        } else if let value = try container.decodeIfPresent(Response.self, forKey: .response) {
            self.body = .response(value)
        } else if let value = try container.decodeIfPresent(SessionBranchEvent.self, forKey: .branch) {
            self.body = .branch(value)
        } else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "log entry \(seq) has no known body"
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seq, forKey: .seq)
        try container.encode(time, forKey: .time)
        try container.encodeIfPresent(run, forKey: .run)

        switch body {
        case .state(let value):
            try container.encode(value, forKey: .state)
        case .observation(let value):
            try container.encode(value, forKey: .observation)
        case .request(let value):
            try container.encode(value, forKey: .request)
        case .message(let value):
            try container.encode(value, forKey: .message)
        case .call(let value):
            try container.encode(value, forKey: .call)
        case .response(let value):
            try container.encode(value, forKey: .response)
        case .branch(let value):
            try container.encode(value, forKey: .branch)
        }
    }
}
