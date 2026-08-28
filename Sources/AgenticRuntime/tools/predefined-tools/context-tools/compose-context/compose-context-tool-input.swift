public struct ComposeContextToolInput: Sendable, Codable, Hashable {
    public let plan: ContextCompositionPlan
    public let maxCharacters: Int?

    public init(
        plan: ContextCompositionPlan,
        maxCharacters: Int? = nil
    ) {
        self.plan = plan
        self.maxCharacters = maxCharacters
    }
}
