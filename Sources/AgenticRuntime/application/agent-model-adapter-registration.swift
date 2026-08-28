import Agentic

public struct AgentModelAdapterRegistration:
    Sendable
{
    public let identifier: AgentModelAdapterIdentifier

    private let makeHandler:
        @Sendable () async throws -> any AgentModelAdapter

    public init(
        identifier: AgentModelAdapterIdentifier,
        make: @escaping @Sendable () async throws -> any AgentModelAdapter
    ) {
        self.identifier = identifier
        self.makeHandler = make
    }

    public func make() async throws -> any AgentModelAdapter {
        try await makeHandler()
    }
}

public func adapter(
    _ identifier: AgentModelAdapterIdentifier,
    make: @escaping @Sendable () async throws -> any AgentModelAdapter
) -> AgentModelAdapterRegistration {
    .init(
        identifier: identifier,
        make: make
    )
}
