import Agentic
import Foundation
import Primitives
import Schema

/// Runtime execution remains a separate concern from bound typed preparation.
public extension InferenceBinding {
    func execute(
        input: JSONValue,
        realization: InferenceRealizationConfiguration? = nil,
        using executor: any InferenceExecuting,
        context: InferenceExecutionContext = .default
    ) async throws -> InferenceInvocation.Response {
        let prepared = try invocation(
            input: input,
            realization: realization,
            context: context
        )
        return try await executor.execute(prepared)
    }
}

public enum InferenceRegistryError: Error, Sendable, LocalizedError {
    case duplicateInference(InferenceIdentifier)
    case unknownInference(InferenceIdentifier)

    public var errorDescription: String? {
        switch self {
        case .duplicateInference(let identifier):
            return "Inference '\(identifier.rawValue)' is installed more than once."
        case .unknownInference(let identifier):
            return "No executable Inference is installed for '\(identifier.rawValue)'."
        }
    }
}

