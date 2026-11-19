import Agentic

public extension Run.Event {
    /// Which model served one request, against what was selected.
    struct Route: Sendable, Codable, Hashable {
        public let profileID: AgentModelProfileIdentifier
        public let title: String
        public let gateway: AgentModelGatewayIdentifier
        public let model: String
        public let tier: AgentModelTier?
        /// The profile the selection preferred, when it named one.
        public let preferredProfileID: AgentModelProfileIdentifier?
        /// The request went elsewhere than the selection asked: only with
        /// fallback explicitly allowed.
        public let isRerouted: Bool
        /// Why, from the routing diagnostics, when rerouted.
        public let reason: String?

        public init(
            profileID: AgentModelProfileIdentifier,
            title: String,
            gateway: AgentModelGatewayIdentifier,
            model: String,
            tier: AgentModelTier?,
            preferredProfileID: AgentModelProfileIdentifier?,
            isRerouted: Bool,
            reason: String?
        ) {
            self.profileID = profileID
            self.title = title
            self.gateway = gateway
            self.model = model
            self.tier = tier
            self.preferredProfileID = preferredProfileID
            self.isRerouted = isRerouted
            self.reason = reason
        }
    }
}

extension AgentLoop {
    /// Records which model served the request. A request served by another
    /// model than the selection named is a change the operator sees.
    func recordRoute(
        _ record: AgentModelRouteRecord,
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let profile = record.route.profile
        await served.record(profile.capabilities)
        let preferences = model.selection.preferences
        let rerouted = preferences.preferredProfileIdentifier.map { $0 != profile.identifier } == true
            || preferences.preferredModelID.map { $0 != profile.modelID } == true
            || (!preferences.gatewayChain.isEmpty && !preferences.gatewayChain.contains(profile.gatewayIdentifier))
        let reason = rerouted
            ? record.diagnostics.compactMap(\.message).joined(separator: " ")
            : nil
        let title = profile.title ?? profile.identifier.rawValue
        let route = Run.Event.Route(
            profileID: profile.identifier,
            title: title,
            gateway: profile.gatewayIdentifier,
            model: profile.model,
            tier: profile.tier,
            preferredProfileID: preferences.preferredProfileIdentifier,
            isRerouted: rerouted,
            reason: reason?.isEmpty == false ? reason : nil
        )
        try await appendRunEvent(
            .init(
                kind: .model_routed,
                iteration: checkpoint.state.iteration,
                summary: rerouted
                    ? "\(preferences.preferredProfileIdentifier?.rawValue ?? "selection") → \(title) · \(profile.gatewayIdentifier.rawValue)"
                    : "\(title) · \(profile.gatewayIdentifier.rawValue)",
                route: route
            ),
            to: &checkpoint
        )
    }
}
