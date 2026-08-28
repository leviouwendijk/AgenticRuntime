import Agentic
import Foundation

public struct AgentSession: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public var messages: [AgentMessage]

    public init(
        id: String,
        messages: [AgentMessage] = []
    ) {
        self.id = id
        self.messages = messages
    }
}

public extension AgentSession {
    init(
        messages: [AgentMessage] = []
    ) {
        self.init(
            id: UUID().uuidString,
            messages: messages
        )
    }
}
