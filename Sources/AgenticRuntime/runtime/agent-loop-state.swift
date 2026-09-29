import Agentic

public struct AgentLoopState: Sendable, Codable, Hashable {
    public var iteration: Int
    public var messages: [Message]

    public init(
        iteration: Int = 0,
        messages: [Message] = []
    ) {
        self.iteration = iteration
        self.messages = messages
    }
}
