import Agentic

public struct CompactionTrigger: Sendable, Codable, Hashable {
    public var maxMessageCount: Int?
    public var maxApproximateCharacterCount: Int?
    public var minimumCompactedMessageCount: Int

    public init(
        maxMessageCount: Int? = 40,
        maxApproximateCharacterCount: Int? = nil,
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
        messages: [AgentMessage]
    ) -> Bool {
        if let maxMessageCount,
           messages.count > maxMessageCount {
            return true
        }

        if let maxApproximateCharacterCount,
           approximateCharacterCount(
                in: messages
           ) > maxApproximateCharacterCount {
            return true
        }

        return false
    }

    func approximateCharacterCount(
        in messages: [AgentMessage]
    ) -> Int {
        messages.reduce(into: 0) { partial, message in
            partial += approximateCharacterCount(
                in: message
            )
        }
    }

    func approximateCharacterCount(
        in message: AgentMessage
    ) -> Int {
        message.content.blocks.reduce(into: 0) { partial, block in
            switch block {
            case .text(let value):
                partial += value.count

            case .tool_call(let value):
                partial += 64 + value.name.count

            case .tool_result(let value):
                partial += 96 + (value.name?.count ?? 0)
            }
        }
    }
}
