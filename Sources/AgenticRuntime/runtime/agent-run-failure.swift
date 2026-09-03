import Foundation

public struct AgentRunFailure: Sendable, Codable, Hashable {
    public enum Kind: String, Sendable, Codable, Hashable, CaseIterable {
        case maximum_iterations_exceeded
    }

    public let kind: Kind
    public let message: String
    public let metadata: [String: String]

    public init(
        kind: Kind,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.kind = kind
        self.message = message
        self.metadata = metadata
    }

    public static func maximumIterationsExceeded(
        _ maximumIterations: Int
    ) -> Self {
        .init(
            kind: .maximum_iterations_exceeded,
            message: "Agent loop exceeded the configured maximum iteration count of \(maximumIterations).",
            metadata: [
                "maximum_iterations": String(maximumIterations),
            ]
        )
    }
}
