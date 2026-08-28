public enum AgentHomeKind: String, Sendable, Codable, Hashable, CaseIterable {
    case user_global
    case project_local
    case ephemeral
}
