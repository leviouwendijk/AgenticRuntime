public enum AgentSessionStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case active
    case awaiting_approval
    case awaiting_user_input
    case completed
    case archived
}
