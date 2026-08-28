import Foundation

public enum AgentRunLoopError: Error, Sendable, LocalizedError {
    case maximumIterationsExceeded(Int)

    public var errorDescription: String? {
        switch self {
        case .maximumIterationsExceeded(let value):
            return "Agent loop exceeded the configured maximum iteration count of \(value)."
        }
    }
}
