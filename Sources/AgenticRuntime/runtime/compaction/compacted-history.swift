import Foundation

public struct CompactedHistory: Sendable, Codable, Hashable {
    public let summaryMessageID: String
    public let replacedMessageCount: Int
    public let retainedMessageCount: Int
    public let estimatedCharactersCompacted: Int
    public let createdAt: Date

    public init(
        summaryMessageID: String,
        replacedMessageCount: Int,
        retainedMessageCount: Int,
        estimatedCharactersCompacted: Int,
        createdAt: Date = Date()
    ) {
        self.summaryMessageID = summaryMessageID
        self.replacedMessageCount = replacedMessageCount
        self.retainedMessageCount = retainedMessageCount
        self.estimatedCharactersCompacted = estimatedCharactersCompacted
        self.createdAt = createdAt
    }
}
