import Foundation

public enum AgentStreamingError: Error, Sendable, LocalizedError {
    case missingCompletedResponse
    case receivingModelResponseCheckpoint(String)
    case interruptedCheckpoint(String)
    case failedCheckpoint(String)

    public var errorDescription: String? {
        switch self {
        case .missingCompletedResponse:
            return "The model stream ended without a completed AgentResponse event."

        case .receivingModelResponseCheckpoint(let sessionID):
            return "Session '\(sessionID)' is currently marked as receiving a model response and cannot be resumed as a normal loop checkpoint."

        case .interruptedCheckpoint(let sessionID):
            return "Session '\(sessionID)' was interrupted during model streaming."

        case .failedCheckpoint(let sessionID):
            return "Session '\(sessionID)' failed during model streaming."
        }
    }
}
