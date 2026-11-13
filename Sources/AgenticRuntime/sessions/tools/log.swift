import Agentic
import Foundation
import Primitives
import Schema
import Macros

/// Self-review over this session's `Run.Log`: every step every run took,
/// including failures, denials, skips and command output that never reached
/// the model's context. The host installs the session's log as a service.
public extension Sessions.Tools {
    @Tool("read_session_log")
    struct Log: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            /// Only these kinds; all when omitted.
            public let kinds: [Run.Log.Entry.Kind]?
            /// Only entries of this run.
            public let run: String?
            /// Start after this sequence number.
            public let after: Int?
            /// Defaults to 50 entries.
            public let limit: Int?
            /// Read the most recent entries first.
            public let latestFirst: Bool

            public init(
                kinds: [Run.Log.Entry.Kind]? = nil,
                run: String? = nil,
                after: Int? = nil,
                limit: Int? = nil,
                latestFirst: Bool = false
            ) {
                self.kinds = kinds
                self.run = run
                self.after = after
                self.limit = limit
                self.latestFirst = latestFirst
            }
        }

        @JSONSchema
        public struct Line: HashableResult {
            public let seq: Int
            public let time: Date
            public let run: String?
            public let kind: Run.Log.Entry.Kind
            public let summary: String

            public init(_ entry: Run.Log.Entry) {
                self.seq = entry.seq
                self.time = entry.time
                self.run = entry.run
                self.kind = entry.kind
                self.summary = entry.summary
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let session: String
            public let totalEntryCount: Int
            public let lines: [Line]
        }

        public static let purpose =
            "List the steps of this session's durable log: requests, messages, calls, responses, approvals, denials, skips, failures, command output. One line each; read a step in full with read_session_step."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Read this session's log.",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let log = try context.require(Run.Log.self)
            let contents = try await log.read()
            var entries = contents.entries.filter { entry in
                (input.kinds.map { $0.contains(entry.kind) } ?? true)
                    && (input.run.map { $0 == entry.run } ?? true)
                    && (input.after.map { entry.seq > $0 } ?? true)
            }
            if input.latestFirst {
                entries.reverse()
            }
            return .init(
                session: contents.header.session,
                totalEntryCount: contents.entries.count,
                lines: entries.prefix(max(1, input.limit ?? 50)).map(Line.init)
            )
        }
    }

    @Tool("read_session_step")
    struct Step: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            /// The step's sequence number from read_session_log.
            public let seq: Int

            public init(seq: Int) {
                self.seq = seq
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let line: Log.Line
            /// The entry with its stored bodies filled in. A request lists
            /// its messages by id, role and digest; read one with
            /// read_session_payload.
            public let detail: JSONValue
        }

        public static let purpose =
            "Read one step of this session's log in full: the exact input of a call, the full response, the event, or the composition of a model request."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Read step \(input.seq) of this session's log.",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let log = try context.require(Run.Log.self)
            guard let entry = try await log.read().entries.first(where: { $0.seq == input.seq }) else {
                throw SessionLogToolError.stepNotFound(input.seq)
            }
            return .init(
                line: .init(entry),
                detail: try detail(of: entry, in: log)
            )
        }

        private func detail(
            of entry: Run.Log.Entry,
            in log: Run.Log
        ) throws -> JSONValue {
            switch entry.body {
            case .state(let state):
                return try JSONValue.encoding(state)
            case .observation(let observation):
                return try JSONValue.encoding(observation)
            case .branch(let event):
                return try JSONValue.encoding(event)
            case .message(let stored):
                return try log.payload(stored.digest, as: JSONValue.self)
            case .response(let response):
                return try log.payload(response.digest, as: JSONValue.self)
            case .call(let call):
                return .object([
                    "call": try JSONValue.encoding(call.call),
                    "input": try log.payload(call.input, as: JSONValue.self),
                ])
            case .request(let request):
                let messages = try request.messages.map { digest in
                    let message = try log.payload(digest, as: Message.self)
                    return JSONValue.object([
                        "id": .string(message.id),
                        "role": .string(message.role.rawValue),
                        "digest": .string(digest.rawValue),
                    ])
                }
                let tools = try log.payload(request.tools, as: [ToolDescriptor].self)
                return .object([
                    "usage": try JSONValue.encoding(request.usage),
                    "messages": .array(messages),
                    "tools": .array(tools.map { .string($0.identifier.rawValue) }),
                ])
            }
        }
    }

    @Tool("read_session_payload")
    struct Payload: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            /// A digest named by read_session_step.
            public let digest: String

            public init(digest: String) {
                self.digest = digest
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let digest: String
            public let value: JSONValue
        }

        public static let purpose =
            "Read a stored body of this session's log by its digest, e.g. one message of a recorded model request."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Read payload \(input.digest.prefix(12)) of this session's log.",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let log = try context.require(Run.Log.self)
            return .init(
                digest: input.digest,
                value: try log.payload(.init(rawValue: input.digest), as: JSONValue.self)
            )
        }
    }
}

public enum SessionLogToolError: Error, Sendable, Equatable, LocalizedError {
    case stepNotFound(Int)

    public var errorDescription: String? {
        switch self {
        case .stepNotFound(let seq):
            "No step \(seq) in this session's log."
        }
    }
}
