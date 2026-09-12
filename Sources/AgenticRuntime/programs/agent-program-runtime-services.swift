import Agentic
import AgenticExecution
import AgenticInference
import AgenticPrograms
import Foundation
import Primitives

/// Runtime observations produced while realizing one semantic inference.
///
/// The typed output continues through the program. Provider usage, routing,
/// and other execution facts remain on the execution record instead of being
/// mixed into the semantic value.
public struct AgentProgramInferenceExecution<Output: Sendable>:
    Sendable
{
    public var output: Output
    public var usage: AgentUsage?
    public var route: AgentModelRouteRecord?
    public var metadata: [String: String]

    public init(
        output: Output,
        usage: AgentUsage? = nil,
        route: AgentModelRouteRecord? = nil,
        metadata: [String: String] = [:]
    ) {
        self.output = output
        self.usage = usage
        self.route = route
        self.metadata = metadata
    }
}

/// Runtime-side execution seam for a realized semantic inference.
///
/// AgenticPrograms owns the semantic inference and realization values. Runtime
/// implementations decide how that realization reaches a model broker or other
/// inference backend and return both the typed semantic output and observable
/// execution facts.
public protocol AgentProgramInferenceExecuting: Sendable {
    func infer<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentProgramInferenceExecution<Inference.Output>
}

/// Runtime-side raw tool boundary used by AgentProgramRunner.
///
/// A governed AgenticExecution adapter can satisfy this later without exposing
/// JSON lowering to authored AgentProgram implementations.
public protocol AgentProgramToolExecuting: Sendable {
    func invoke(
        _ identifier: AgentToolIdentifier,
        input: JSONValue
    ) async throws -> JSONValue

    func resume(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    ) async throws -> JSONValue
}

public extension AgentProgramToolExecuting {
    func resume(
        pendingApproval: PendingApproval,
        decision _: ApprovalDecision
    ) async throws -> JSONValue {
        throw AgentProgramReplayError.tool_resume_unsupported(
            AgentToolIdentifier(
                pendingApproval.toolCall.name
            )
        )
    }
}

public enum AgentProgramRuntimeError:
    Error,
    Sendable,
    LocalizedError
{
    case missingInferenceRealization(
        site: AgentInferenceSiteIdentifier,
        inference: AgentInferenceIdentifier
    )
    case inferenceRealizationMismatch(
        site: AgentInferenceSiteIdentifier,
        expected: AgentInferenceIdentifier,
        actual: AgentInferenceIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .missingInferenceRealization(
            let site,
            let inference
        ):
            return "No realization is bound to inference site '\(site.rawValue)' for inference '\(inference.rawValue)'."

        case .inferenceRealizationMismatch(
            let site,
            let expected,
            let actual
        ):
            return "Inference site '\(site.rawValue)' expects '\(expected.rawValue)' but its realization is bound to '\(actual.rawValue)'."
        }
    }
}
