public enum HistoryPersistenceMode: String, Sendable, Codable, Hashable, CaseIterable {
    case disabled
    case checkpointmutation
}
