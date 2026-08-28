public struct ContextCompositionPlan: Sendable, Codable, Hashable {
    public var metadata: ContextMetadata
    public var sources: [ContextSource]

    public init(
        metadata: ContextMetadata = .init(),
        sources: [ContextSource] = []
    ) {
        self.metadata = metadata
        self.sources = sources
    }
}
