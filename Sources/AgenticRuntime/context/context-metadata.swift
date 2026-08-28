public struct ContextMetadata: Sendable, Codable, Hashable {
    public var title: String?
    public var details: String?
    public var attributes: [String: String]

    public init(
        title: String? = nil,
        details: String? = nil,
        attributes: [String: String] = [:]
    ) {
        self.title = title
        self.details = details
        self.attributes = attributes
    }
}
