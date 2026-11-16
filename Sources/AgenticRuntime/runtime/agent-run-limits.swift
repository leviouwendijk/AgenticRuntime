public struct AgentRunLimits:
    Sendable,
    Codable,
    Hashable
{
    public var iterations: Int?

    public init(
        iterations: Int? = nil
    ) {
        self.iterations = iterations
    }

    public static let unlimited = Self()
    public static let `default` = Self(
        iterations: 12
    )
}

public enum AgentRunLimitExhaustion:
    Sendable,
    Codable,
    Hashable
{
    case iterations(
        limit: Int,
        consumed: Int
    )
    /// The next request would not fit its input limit. Nothing was sent
    /// and nothing was dropped; compacting (or a larger limit) lets the
    /// run continue from here.
    case context(
        estimatedInputTokens: Int,
        limit: Int,
        compactable: Int
    )

    public var summary: String {
        switch self {
        case .iterations(let limit, let consumed):
            return "Agent run reached its iteration limit of \(limit) after consuming \(consumed) iteration(s)."
        case .context(let estimated, let limit, let compactable):
            return "The next request (≈\(estimated) tokens) would not fit its input limit of \(limit). "
                + "Nothing was sent. "
                + (compactable > 0
                    ? ":compact would free ≈\(compactable) tokens; then continue."
                    : "Nothing older can be compacted; stop, or continue in a fresh context.")
        }
    }
}

public enum AgentRunLimitResolution:
    Sendable,
    Codable,
    Hashable
{
    case continue_with(AgentRunLimits)
    case stop
}
