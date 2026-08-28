public struct EstimateContextSizeToolOutput: Sendable, Codable, Hashable {
    public let metadata: ContextMetadata
    public let inspection: ContextPlanInspection
    public let size: ContextSizeEstimate?
    public let composed: Bool

    public init(
        metadata: ContextMetadata,
        inspection: ContextPlanInspection,
        size: ContextSizeEstimate?,
        composed: Bool
    ) {
        self.metadata = metadata
        self.inspection = inspection
        self.size = size
        self.composed = composed
    }
}
