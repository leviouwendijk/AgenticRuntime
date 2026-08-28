public protocol AgentSessionMetadataStore: Sendable {
    func load(
        sessionID: String
    ) throws -> AgentSessionMetadata?

    func save(
        _ metadata: AgentSessionMetadata
    ) throws

    func delete(
        sessionID: String
    ) throws
}
