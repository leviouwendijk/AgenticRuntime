public struct InspectContextSourcesToolOutput: Sendable, Codable, Hashable {
    public let metadata: ContextMetadata
    public let inspection: ContextPlanInspection

    public init(
        metadata: ContextMetadata,
        inspection: ContextPlanInspection
    ) {
        self.metadata = metadata
        self.inspection = inspection
    }
}
