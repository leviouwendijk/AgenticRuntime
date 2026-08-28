public struct EstimateContextSizeToolInput: Sendable, Codable, Hashable {
    public let plan: ContextCompositionPlan
    public let compose: Bool?

    public init(
        plan: ContextCompositionPlan,
        compose: Bool? = nil
    ) {
        self.plan = plan
        self.compose = compose
    }

    public var shouldCompose: Bool {
        compose ?? true
    }
}
