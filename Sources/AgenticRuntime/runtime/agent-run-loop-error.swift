import Foundation

public enum AgentRunLoopError: Error, Sendable, LocalizedError {
    case maximumIterationsExceeded(Int)

    public var errorDescription: String? {
        switch self {
        case .maximumIterationsExceeded(let value):
            return AgentRunFailure.maximumIterationsExceeded(
                value
            ).message
        }
    }
}
