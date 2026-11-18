import Agentic

public struct ApplicationModelSelection: Sendable, Codable, Hashable {
    public let preferences: AgentModelPreferences
    /// Application bindings per route purpose. An Agent declares only its
    /// purpose; the application decides which model and gateways serve it.
    public let purposes: [AgentModelRoutePurpose: AgentModelPreferences]
    public let precedence: ModelSelectionPrecedence

    public init(
        preferences: AgentModelPreferences = .init(),
        purposes: [AgentModelRoutePurpose: AgentModelPreferences] = [:],
        precedence: ModelSelectionPrecedence = .default
    ) {
        self.preferences = preferences
        self.purposes = purposes
        self.precedence = precedence
    }

    /// The application default for one purpose: its binding layered over
    /// the general default.
    public func preferences(
        for purpose: AgentModelRoutePurpose
    ) -> AgentModelPreferences {
        guard let bound = purposes[purpose] else {
            return preferences
        }
        return preferences.overriding(
            with: bound
        )
    }

    private enum CodingKeys: String, CodingKey {
        case preferences
        case purposes
        case precedence
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            preferences: try values.decode(AgentModelPreferences.self, forKey: .preferences),
            purposes: try values.decodeIfPresent(
                [AgentModelRoutePurpose: AgentModelPreferences].self,
                forKey: .purposes
            ) ?? [:],
            precedence: try values.decode(ModelSelectionPrecedence.self, forKey: .precedence)
        )
    }
}

public enum ApplicationModelSelectionError: Error, Sendable, Hashable {
    case unavailable_profile(AgentModelProfileIdentifier)
    case unavailable_model(AgentModelID, AgentModelGatewayIdentifier?)
    case unavailable_gateway(AgentModelGatewayIdentifier)
}

extension ApplicationModelSelection {
    /// Fail at startup when a configured default cannot route at all. A
    /// gateway chain is satisfied by any one of its gateways. A default that
    /// allows fallback only has to name an installed target: when its
    /// gateway is unconfigured, routing falls back instead of failing.
    func validate(
        against routable: ProfileCatalog,
        installed: ProfileCatalog
    ) throws {
        for preferred in [preferences] + purposes.values.map(preferences.overriding(with:)) {
            try Self.validate(
                preferred,
                against: preferred.allowsFallback ? installed : routable
            )
        }
    }

    private static func validate(
        _ preferred: AgentModelPreferences,
        against routable: ProfileCatalog
    ) throws {
        let chain = preferred.gatewayChain

        if let profile = preferred.preferredProfileIdentifier,
           routable.profilesByIdentifier[profile] == nil
        {
            throw ApplicationModelSelectionError.unavailable_profile(profile)
        }
        if let model = preferred.preferredModelID,
           !routable.profiles(for: model).contains(where: {
               chain.isEmpty || chain.contains($0.gatewayIdentifier)
           })
        {
            throw ApplicationModelSelectionError.unavailable_model(model, chain.first)
        }
        if let gateway = chain.first,
           !routable.profilesByIdentifier.values.contains(where: {
               chain.contains($0.gatewayIdentifier)
           })
        {
            throw ApplicationModelSelectionError.unavailable_gateway(gateway)
        }
    }
}
