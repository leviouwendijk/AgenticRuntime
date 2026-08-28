public struct AgentStreamCheckpointPolicy: Sendable, Codable, Hashable {
    public var eventInterval: Int
    public var characterInterval: Int
    public var minimumSecondsBetweenCheckpoints: Double

    public init(
        eventInterval: Int = 25,
        characterInterval: Int = 2_000,
        minimumSecondsBetweenCheckpoints: Double = 1.0
    ) {
        self.eventInterval = max(1, eventInterval)
        self.characterInterval = max(1, characterInterval)
        self.minimumSecondsBetweenCheckpoints = max(
            0,
            minimumSecondsBetweenCheckpoints
        )
    }

    public static let `default` = Self()
}
