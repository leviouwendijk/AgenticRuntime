import Agentic

public func gateway(
    _ identifier: AgentModelGatewayIdentifier,
    make: @escaping @Sendable () async throws
        -> any AgentModelGateway
) -> AgentModelGatewayFactory {
    .init(
        identifier: identifier,
        make: make
    )
}
