import Errors
import Foundation

public struct AgentRunFailure: Sendable, Codable, Hashable {
    public enum Kind: String, Sendable, Codable, Hashable, CaseIterable {
        case maximum_iterations_exceeded
        case model_invocation_failed
    }

    public let kind: Kind
    public let message: String
    public let metadata: [String: String]
    public let report: ErrorReport?

    public init(
        kind: Kind,
        message: String,
        metadata: [String: String] = [:],
        report: ErrorReport? = nil
    ) {
        self.kind = kind
        self.message = message
        self.metadata = metadata
        self.report = report
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

    public static func modelInvocationFailed(
        _ error: Error
    ) -> Self {
        let nsError = error as NSError
        var metadata = [
            "error_domain": nsError.domain,
            "error_code": String(nsError.code),
        ]

        for (key, value) in nsError.userInfo {
            guard key.hasPrefix("agentic_"),
                  let value = value as? String
            else {
                continue
            }

            metadata[String(key.dropFirst("agentic_".count))] =
                value
        }

        return .init(
            kind: .model_invocation_failed,
            message: error.localizedDescription,
            metadata: metadata,
            report: error.report
        )
    }
}
