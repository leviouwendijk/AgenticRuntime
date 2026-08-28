public struct MessageRetentionPolicy: Sendable, Codable, Hashable {
    public var preserveLeadingSystemMessages: Bool
    public var preserveRecentMessageCount: Int

    public init(
        preserveLeadingSystemMessages: Bool = true,
        preserveRecentMessageCount: Int = 12
    ) {
        self.preserveLeadingSystemMessages = preserveLeadingSystemMessages
        self.preserveRecentMessageCount = max(0, preserveRecentMessageCount)
    }

    public static let `default` = Self()
}
