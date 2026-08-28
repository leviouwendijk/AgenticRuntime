public struct ComposeContextToolOutput: Sendable, Codable, Hashable {
    public let metadata: ContextMetadata
    public let content: String
    public let size: ContextSizeEstimate
    public let inspection: ContextPlanInspection
    public let truncated: Bool

    public init(
        metadata: ContextMetadata,
        content: String,
        size: ContextSizeEstimate,
        inspection: ContextPlanInspection,
        truncated: Bool
    ) {
        self.metadata = metadata
        self.content = content
        self.size = size
        self.inspection = inspection
        self.truncated = truncated
    }
}
