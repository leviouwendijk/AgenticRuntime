public protocol AgentInteractionProviding:
    Sendable
{
    func resolve(
        _ request: Run.Interaction.Request
    ) async throws -> Run.Interaction.Response
}
