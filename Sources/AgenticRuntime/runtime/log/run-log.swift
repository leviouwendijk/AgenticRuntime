import Agentic
import Foundation
import IO
import Readers

public extension Run {
    /// Append-only record of every step a session takes, across all of its
    /// runs. Large bodies (messages, inputs, responses, requests) are stored
    /// once by content digest and referenced from the entries.
    ///
    /// The log is evidence, not context: nothing here enters a model request
    /// unless the context allocator selects it.
    actor Log {
        public let session: String
        public let file: URL
        public let payloads: URL
        public let durability: Durability

        private var destination: Destination
        private var seq: Int
        private var stored: Set<Digest>

        /// Opens `file` for appending, continuing its sequence when it
        /// already holds entries.
        /// `metadata` is recorded in the header of a new log only.
        public init(
            session: String,
            file: URL,
            payloads: URL,
            durability: Durability = .entry,
            metadata: [String: String] = [:]
        ) throws {
            try FileSystem.default.directory.create(file.deletingLastPathComponent())
            try FileSystem.default.directory.create(payloads)

            let existing = try DataFileReader(file).read(
                options: .init(missingFilePolicy: .returnEmpty)
            ).data
            var destination = Destination(
                try SystemFileDestination(path: file.path, mode: .append)
            )

            if existing.isEmpty {
                try Self.write(
                    Self.line(Header(session: session, metadata: metadata)),
                    to: &destination
                )
                self.seq = 0
            } else {
                // A torn last line (crash mid-write) is closed off; readers
                // skip it.
                if existing.last != 0x0A {
                    try Self.write(Data([0x0A]), to: &destination)
                }
                self.seq = try Self.entries(in: existing).last?.seq ?? 0
            }
            _ = try destination.flush()

            self.session = session
            self.file = file
            self.payloads = payloads
            self.durability = durability
            self.destination = destination
            self.stored = []
        }

        /// The log's sink for one run: every entry it records names that run.
        public nonisolated func recorder(
            run: String
        ) -> Recorder {
            .init(log: self, run: run)
        }

        @discardableResult
        public func append(
            _ body: Entry.Body,
            run: String?
        ) throws -> Entry {
            seq += 1
            let entry = Entry(seq: seq, run: run, body: body)
            try Self.write(Self.line(entry), to: &destination)

            switch durability {
            case .buffered:
                break
            case .entry:
                _ = try destination.flush()
            case .synced:
                _ = try destination.synchronize()
            }
            return entry
        }

        /// Writes staged entries; a step boundary for `.buffered` logs.
        public func flush() throws {
            switch durability {
            case .buffered, .entry:
                _ = try destination.flush()
            case .synced:
                _ = try destination.synchronize()
            }
        }

        /// Stores `value` under its digest unless already stored.
        public func store(
            _ value: some Encodable
        ) throws -> Digest {
            let data = try Self.encoder.encode(value)
            let digest = Digest(data)
            guard !stored.contains(digest) else {
                return digest
            }

            let url = Self.payload(digest, in: payloads)
            if !FileSystem.default.exists(url) {
                // Written beside its final name and moved into place, so a
                // payload is either absent or complete.
                let partial = url.appendingPathExtension("partial")
                if FileSystem.default.exists(partial) {
                    try FileSystem.default.remove(partial)
                }
                var payload = Destination(
                    try SystemFileDestination(path: partial.path, mode: .create)
                )
                try Self.write(data, to: &payload)
                if durability == .synced {
                    _ = try payload.synchronize()
                } else {
                    _ = try payload.flush()
                }
                try FileSystem.default.move(partial, to: url)
            }
            stored.insert(digest)
            return digest
        }
    }
}

public extension Run.Log {
    /// Records the Run.EventSink channel into the log for one run.
    struct Recorder: Run.EventSink {
        public let log: Run.Log
        public let run: String

        public func record(_ event: Run.Event) async throws {
            switch event {
            case .state(let state):
                try await log.append(.state(state), run: run)
            case .tool_observation(let observation):
                try await log.append(.observation(observation), run: run)
            case .request(let request):
                try await log.append(.request(try await log.entry(for: request)), run: run)
            }
        }

        public func recordMessage(_ message: Message) async throws {
            let digest = try await log.store(message)
            try await log.append(.message(.init(id: message.id, digest: digest)), run: run)
        }

        public func recordFunctionCall(_ functionCall: FunctionCall) async throws {
            let input = try await log.store(functionCall.input)
            try await log.append(.call(.init(call: functionCall.reference, input: input)), run: run)
        }

        public func recordToolResult(_ result: FunctionCall.Response) async throws {
            let digest = try await log.store(result)
            try await log.append(
                .response(.init(call: result.call, isError: result.isError, digest: digest)),
                run: run
            )
        }

        public func recordSessionBranch(_ event: SessionBranchEvent) async throws {
            try await log.append(.branch(event), run: run)
        }

        public func flush() async throws {
            try await log.flush()
        }
    }
}

extension Run.Log {
    func entry(
        for request: Run.Event.Request
    ) throws -> Entry.Request {
        var options = request.request
        options.messages = []
        options.tools = []
        return .init(
            messages: try request.request.messages.map { try store($0) },
            tools: try store(request.request.tools),
            options: try store(options),
            usage: request.usage
        )
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func line(
        _ value: some Encodable
    ) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    static func payload(
        _ digest: Digest,
        in payloads: URL
    ) -> URL {
        payloads.appendingPathComponent("\(digest.rawValue).json")
    }

    /// Entries of a log file's contents. A line that is not JSON at all is
    /// a write torn by a crash and is skipped; JSON that does not decode as
    /// an entry is corruption.
    static func entries(
        in data: Data
    ) throws -> [Entry] {
        try data
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .dropFirst()
            .compactMap { line in
                let line = Data(line)
                guard (try? JSONSerialization.jsonObject(with: line)) != nil else {
                    return nil
                }
                return try decoder.decode(Entry.self, from: line)
            }
    }

    static func write(
        _ data: Data,
        to destination: inout Destination
    ) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let rest = UnsafeRawBufferPointer(rebasing: bytes[offset...])
                switch try destination.write(rest) {
                case .complete:
                    return
                case .partial(let count):
                    offset += count.value
                case .unavailable:
                    guard try destination.flush() == .complete else {
                        throw Run.Log.Failure.unwritable
                    }
                }
            }
        }
    }
}

public extension Run.Log {
    enum Failure: Error, Sendable, Equatable {
        case unwritable
        case missingHeader(URL)
        case unsupportedVersion(Int)
        /// No session, or `candidates` sessions, match the reference.
        case unknownSession(String, candidates: Int)
    }
}
