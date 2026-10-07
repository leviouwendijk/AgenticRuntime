import Foundation

public extension Run.Interaction {
    enum Error:
        Swift.Error,
        Sendable,
        LocalizedError
    {
        case noCurrentSuspension(
            sessionID: String
        )
        case sessionMismatch(
            expected: String,
            received: String
        )
        case requestMismatch(
            expected: String,
            received: String
        )
        case resolutionMismatch(
            expected: Kind,
            received: Kind
        )

        public var errorDescription: String? {
            switch self {
            case .noCurrentSuspension(let sessionID):
                return "Session '\(sessionID)' has no current interaction suspension."

            case .sessionMismatch(
                let expected,
                let received
            ):
                return "Interaction response session '\(received)' does not match current session '\(expected)'."

            case .requestMismatch(
                let expected,
                let received
            ):
                return "Interaction response request '\(received)' does not match current suspension '\(expected)'."

            case .resolutionMismatch(
                let expected,
                let received
            ):
                return "Interaction resolution kind '\(received.rawValue)' does not match required kind '\(expected.rawValue)'."
            }
        }
    }
}

@available(
    *,
    deprecated,
    renamed: "Run.Interaction.Error"
)
public typealias AgentInteractionError = Run.Interaction.Error
