import Agentic

public struct AgentLoopState: Sendable, Codable, Hashable {
    public var iteration: Int
    public var messages: [AgentMessage]

    public init(
        iteration: Int = 0,
        messages: [AgentMessage] = []
    ) {
        self.iteration = iteration
        self.messages = messages
    }
}
