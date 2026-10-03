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

    public var summary: String {
        switch self {
        case .iterations(let limit, let consumed):
            return "Agent run reached its iteration limit of \(limit) after consuming \(consumed) iteration(s)."
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
