public struct CompactionStrategy: Sendable, Codable, Hashable {
    public var trigger: CompactionTrigger
    public var retention: MessageRetentionPolicy
    public var maxExcerptCount: Int
    public var maxExcerptLength: Int

    public init(
        trigger: CompactionTrigger = .default,
        retention: MessageRetentionPolicy = .default,
        maxExcerptCount: Int = 20,
        maxExcerptLength: Int = 240
    ) {
        self.trigger = trigger
        self.retention = retention
        self.maxExcerptCount = max(1, maxExcerptCount)
        self.maxExcerptLength = max(32, maxExcerptLength)
    }

    public static let `default` = Self()
}
