/// Per-request context budget derived from the model route that will serve it,
/// so compaction follows each model's window instead of one fixed cap.
public struct ContextBudget: Sendable, Hashable {
    public var inputTokenLimit: Int?
    /// Share of the input window at which compaction starts.
    public var compactionFraction: Double

    public init(
        inputTokenLimit: Int? = nil,
        compactionFraction: Double = 0.6
    ) {
        self.inputTokenLimit = inputTokenLimit
        self.compactionFraction = min(1, max(0.1, compactionFraction))
    }

    public static let unknown = Self()

    /// Character equivalent of the compaction point, at roughly 4 characters per token.
    public var compactionCharacterCount: Int? {
        inputTokenLimit.map {
            Int(Double($0) * compactionFraction) * 4
        }
    }
}
