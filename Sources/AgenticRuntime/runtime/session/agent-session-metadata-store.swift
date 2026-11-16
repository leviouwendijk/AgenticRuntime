import AgenticSessions
public protocol AgentSessionMetadataStore: Sendable {
    func load(
        sessionID: String
    ) throws -> Sessions.Metadata?

    func save(
        _ metadata: Sessions.Metadata
    ) throws

    func delete(
        sessionID: String
    ) throws
}
