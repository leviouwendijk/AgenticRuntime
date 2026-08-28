public struct ComposedContext: Sendable, Codable, Hashable {
    public let metadata: ContextMetadata
    public let text: String

    public init(
        metadata: ContextMetadata,
        text: String
    ) {
        self.metadata = metadata
        self.text = text
    }
}
