import Agentic

public struct ApplicationModelSelection: Sendable, Codable, Hashable {
    public let preferences: AgentModelPreferences
    public let precedence: ModelSelectionPrecedence

    public init(
        preferences: AgentModelPreferences = .init(),
        precedence: ModelSelectionPrecedence = .default
    ) {
        self.preferences = preferences
        self.precedence = precedence
    }
}

public enum ApplicationModelSelectionError: Error, Sendable, Hashable {
    case unavailable_profile(AgentModelProfileIdentifier)
    case unavailable_model(AgentModelID, AgentModelGatewayIdentifier?)
    case unavailable_gateway(AgentModelGatewayIdentifier)
}
