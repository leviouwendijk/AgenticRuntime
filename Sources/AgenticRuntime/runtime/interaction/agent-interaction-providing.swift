public protocol AgentInteractionProviding:
    Sendable
{
    func resolve(
        _ request: AgentInteraction.Request
    ) async throws -> AgentInteraction.Response
}
