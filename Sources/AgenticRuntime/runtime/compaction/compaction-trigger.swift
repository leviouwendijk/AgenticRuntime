import Agentic
import Foundation

public struct CompactionTrigger: Sendable, Codable, Hashable {
    public var maxMessageCount: Int?
    public var maxApproximateCharacterCount: Int?
    public var minimumCompactedMessageCount: Int

    /// The character count is a fallback for routes without a declared input
    /// limit (roughly 80k tokens); a known ContextBudget takes precedence.
    public init(
        maxMessageCount: Int? = 40,
        maxApproximateCharacterCount: Int? = 320_000,
        minimumCompactedMessageCount: Int = 8
    ) {
        self.maxMessageCount = maxMessageCount
        self.maxApproximateCharacterCount = maxApproximateCharacterCount
        self.minimumCompactedMessageCount = max(1, minimumCompactedMessageCount)
    }

    public static let `default` = Self()
}

public extension CompactionTrigger {
    func shouldCompact(
        messages: [Message],
        budget: ContextBudget = .unknown
    ) -> Bool {
        if let maxMessageCount,
           messages.count > maxMessageCount {
            return true
        }

        if let characterLimit = budget.compactionCharacterCount
            ?? maxApproximateCharacterCount,
           approximateCharacterCount(
                in: messages
           ) > characterLimit {
            return true
        }

        return false
    }

    func approximateCharacterCount(
        in messages: [Message]
    ) -> Int {
        messages.reduce(into: 0) { partial, message in
            partial += approximateCharacterCount(
                in: message
            )
        }
    }

    func approximateCharacterCount(
        in message: Message
    ) -> Int {
        message.content.blocks.reduce(into: 0) { partial, block in
            switch block {
            case .text(let value):
                partial += value.count

            case .resource(let value):
                partial += 64
                partial += value.source.value.count
                partial += value.contentType?.count ?? 0
                partial += value.metadata.title?.count ?? 0
                partial += value.metadata.filename?.count ?? 0

            // Tool payloads are what the provider actually receives, so count
            // their encoded size rather than only the tool name.
            case .call(let value):
                partial += 64 + encodedCharacterCount(of: value)

            case .result(let value):
                partial += 96 + encodedCharacterCount(of: value)
            }
        }
    }

    func encodedCharacterCount<Value: Encodable>(
        of value: Value
    ) -> Int {
        (try? JSONEncoder().encode(value))?.count ?? 0
    }
}
