import Agentic
import Foundation

public enum AgentRegistryError: Error, Sendable, LocalizedError {
    case duplicateAgent(AgentIdentifier)
    case unknownAgent(AgentIdentifier)

    public var errorDescription: String? {
        switch self {
        case .duplicateAgent(let identifier):
            "An Agent with id '\(identifier.rawValue)' is already installed."
        case .unknownAgent(let identifier):
            "Unknown Agent: \(identifier.rawValue)"
        }
    }
}

