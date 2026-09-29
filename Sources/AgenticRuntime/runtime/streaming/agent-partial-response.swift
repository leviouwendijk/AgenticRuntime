import Agentic

public struct AgentPartialResponse: Sendable, Codable, Hashable {
    public var messageID: String
    public var blocks: [MessageContentBlock]
    public var toolCalls: [ToolCall]
    public var metadata: [String: String]

    public init(
        messageID: String,
        blocks: [MessageContentBlock] = [],
        toolCalls: [ToolCall] = [],
        metadata: [String: String] = [:]
    ) {
        self.messageID = messageID
        self.blocks = blocks
        self.toolCalls = toolCalls
        self.metadata = metadata
    }
}

public extension AgentPartialResponse {
    var message: Message {
        .init(
            id: messageID,
            role: .assistant,
            content: .init(
                blocks: blocks
            )
        )
    }

    var textCharacterCount: Int {
        blocks.reduce(
            0
        ) { partial, block in
            guard case .text(let value) = block else {
                return partial
            }

            return partial + value.count
        }
    }
}
