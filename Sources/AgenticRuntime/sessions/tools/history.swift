import Agentic
import Foundation
import Primitives
import Schema
import Macros

public extension Sessions.Tools {
    /// Reads the complete message history of a session, including messages
    /// that compaction removed from the model's context.
    @Tool("read_session_history")
    struct History: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            /// Omit to find `fromMessageID` in any recorded session, as a
            /// compaction pointer names only the message.
            public let sessionID: String?
            /// Start at this message; takes precedence over startIndex.
            public let fromMessageID: String?
            /// Stop after this message, inclusive.
            public let throughMessageID: String?
            public let startIndex: Int?
            /// Defaults to 20 messages.
            public let limit: Int?
            /// Defaults to 40,000 encoded characters; at least one message is always returned.
            public let maxCharacters: Int?

            public init(
                sessionID: String? = nil,
                fromMessageID: String? = nil,
                throughMessageID: String? = nil,
                startIndex: Int? = nil,
                limit: Int? = nil,
                maxCharacters: Int? = nil
            ) {
                self.sessionID = sessionID
                self.fromMessageID = fromMessageID
                self.throughMessageID = throughMessageID
                self.startIndex = startIndex
                self.limit = limit
                self.maxCharacters = maxCharacters
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let sessionID: String
            public let totalMessageCount: Int
            public let startIndex: Int
            public let returnedMessageCount: Int
            /// Pass as startIndex to continue; nil when the requested range is exhausted.
            public let nextIndex: Int?
            public let messages: [Message]

            public init(
                sessionID: String,
                totalMessageCount: Int,
                startIndex: Int,
                nextIndex: Int?,
                messages: [Message]
            ) {
                self.sessionID = sessionID
                self.totalMessageCount = totalMessageCount
                self.startIndex = startIndex
                self.returnedMessageCount = messages.count
                self.nextIndex = nextIndex
                self.messages = messages
            }
        }

        public static let purpose =
            "Read a session's complete message history, including results compacted out of your context. Use the message ID a compaction pointer names (the session ID is optional); page with nextIndex."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in _: ToolContext
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Read message history for "
                    + (input.sessionID.map { "session \($0)" } ?? "message \(input.fromMessageID ?? "?")") + ".",
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let history = try context.require(AgentSessionHistory.self)
            let sessionID = try await resolveSession(input, in: history)

            guard let messages = await history.messages(
                sessionID: sessionID
            ) else {
                throw SessionHistoryToolError.sessionNotFound(
                    sessionID
                )
            }

            let lower = try index(
                of: input.fromMessageID,
                in: messages
            ) ?? max(0, input.startIndex ?? 0)
            let upper = try index(
                of: input.throughMessageID,
                in: messages
            ) ?? messages.count - 1

            guard lower <= upper, lower < messages.count else {
                return Output(
                    sessionID: sessionID,
                    totalMessageCount: messages.count,
                    startIndex: lower,
                    nextIndex: nil,
                    messages: []
                )
            }

            let limit = max(1, input.limit ?? 20)
            let maxCharacters = max(1, input.maxCharacters ?? 40_000)
            let encoder = JSONEncoder()
            var selected: [Message] = []
            var characters = 0

            for message in messages[lower...upper] {
                guard selected.count < limit else { break }

                let size = (try? encoder.encode(message))?.count ?? 0
                guard selected.isEmpty || characters + size <= maxCharacters else {
                    break
                }

                selected.append(message)
                characters += size
            }

            let next = lower + selected.count

            return Output(
                sessionID: sessionID,
                totalMessageCount: messages.count,
                startIndex: lower,
                nextIndex: next <= upper ? next : nil,
                messages: selected
            )
        }
    }
}

private extension Sessions.Tools.History {
    /// The named session, or the fullest recorded one holding the message.
    func resolveSession(
        _ input: Input,
        in history: AgentSessionHistory
    ) async throws -> String {
        if let sessionID = input.sessionID { return sessionID }
        guard let messageID = input.fromMessageID else {
            throw SessionHistoryToolError.sessionRequired
        }
        var best: (id: String, count: Int)?
        for id in await history.sessionIDs() {
            guard let messages = await history.messages(sessionID: id),
                  messages.contains(where: { $0.id == messageID }),
                  messages.count > (best?.count ?? -1)
            else { continue }
            best = (id, messages.count)
        }
        guard let best else {
            throw SessionHistoryToolError.messageNotFound(messageID)
        }
        return best.id
    }

    func index(
        of messageID: String?,
        in messages: [Message]
    ) throws -> Int? {
        guard let messageID else {
            return nil
        }

        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            throw SessionHistoryToolError.messageNotFound(
                messageID
            )
        }

        return index
    }
}

public enum SessionHistoryToolError:
    Error,
    Sendable,
    LocalizedError
{
    case sessionNotFound(String)
    case messageNotFound(String)
    case sessionRequired

    public var errorDescription: String? {
        switch self {
        case .sessionRequired:
            return "Name a sessionID, or a fromMessageID to find its session."

        case .sessionNotFound(let sessionID):
            return "No recorded history for session \(sessionID)."

        case .messageNotFound(let messageID):
            return "Message \(messageID) is not in this session's history."
        }
    }
}
