import Agentic
import AgenticExecution
import AgenticInference
import AgenticPrograms
import AgenticRecovery
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

/// Runtime observations produced while executing one Program tool operation.
///
/// The semantic JSON output continues toward the authored typed Program API.
/// Recovery evidence remains beside it for Runtime recording and replay.
public struct AgentProgramToolExecution: Sendable {
    struct Failure:
        Error,
        Sendable,
        LocalizedError
    {
        let tool: AgentToolIdentifier
        let recovery: Recovery.Record?

        var errorDescription: String? {
            "Program tool '\(tool.rawValue)' returned a failed tool result."
        }
    }

    public var output: JSONValue
    public var recovery: Recovery.Record?

    public init(
        output: JSONValue,
        recovery: Recovery.Record? = nil
    ) {
        self.output = output
        self.recovery = recovery
    }
}

/// Runtime-side raw tool boundary used by AgentProgramRunner.
///
/// A governed AgenticExecution adapter satisfies this without exposing JSON
/// lowering or recovery bookkeeping to authored AgentProgram implementations.
public protocol AgentProgramToolExecuting: Sendable {
    func invoke(
        _ identifier: AgentToolIdentifier,
        input: JSONValue
    ) async throws -> AgentProgramToolExecution

    func resume(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    ) async throws -> AgentProgramToolExecution
}

public extension AgentProgramToolExecuting {
    func resume(
        pendingApproval: PendingApproval,
        decision _: ApprovalDecision
    ) async throws -> AgentProgramToolExecution {
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
