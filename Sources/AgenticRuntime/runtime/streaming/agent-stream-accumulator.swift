import Agentic

public struct AgentStreamAccumulator: Sendable {
    public private(set) var partial: AgentPartialResponse
    public private(set) var completedResponse: AgentResponse?

    public init(
        messageID: String
    ) {
        self.partial = .init(
            messageID: messageID
        )
    }

    public mutating func consume(
        _ event: AgentStreamEvent
    ) throws {
        switch event {
        case .messagedelta(let block):
            append(
                block
            )

        case .call(let functionCall):
            partial.functionCalls.append(
                functionCall
            )
            append(
                .call(functionCall)
            )

        case .result(let result):
            append(
                .result(result)
            )

        case .completed(let response):
            completedResponse = response
        }
    }

    private mutating func append(
        _ block: MessageContentBlock
    ) {
        guard case .text(let incomingText) = block,
              let last = partial.blocks.last,
              case .text(let existingText) = last
        else {
            partial.blocks.append(
                block
            )
            return
        }

        partial.blocks.removeLast()
        partial.blocks.append(
            .text(existingText + incomingText)
        )
    }
}
