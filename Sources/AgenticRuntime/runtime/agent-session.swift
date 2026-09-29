import Agentic
import Foundation

public struct AgentSession: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public var messages: [Message]

    public init(
        id: String,
        messages: [Message] = []
    ) {
        self.id = id
        self.messages = messages
    }
}

public extension AgentSession {
    init(
        messages: [Message] = []
    ) {
        self.init(
            id: UUID().uuidString,
            messages: messages
        )
    }
}
