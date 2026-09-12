import Agentic
import AgenticPrograms
import Foundation
import Primitives

/// Durable continuation material for an AgentProgram that reaches an
/// interaction boundary.
///
/// Native Swift Programs cannot serialize their async stack directly. Runtime
/// can later resume them by deterministic semantic-step replay: completed steps
/// return their recorded outputs without executing again until control reaches
/// the suspended step.
public struct AgentProgramCheckpoint:
    Sendable,
    Codable,
    Hashable
{
    public var sessionID: String
    public var programIdentifier: AgentProgramIdentifier
    public var programVersion: String?
    public var input: JSONValue
    public var realization: JSONValue?
    public var completedSteps: [AgentProgramStepRecord]
    public var suspendedStep: AgentProgramStepRecord
    public var suspension: AgentSuspension
    public var startedAt: Date
    public var metadata: [String: String]

    public init(
        sessionID: String,
        programIdentifier: AgentProgramIdentifier,
        programVersion: String? = nil,
        input: JSONValue,
        realization: JSONValue? = nil,
        completedSteps: [AgentProgramStepRecord],
        suspendedStep: AgentProgramStepRecord,
        suspension: AgentSuspension,
        startedAt: Date,
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.programIdentifier = programIdentifier
        self.programVersion = programVersion
        self.input = input
        self.realization = realization
        self.completedSteps = completedSteps
        self.suspendedStep = suspendedStep
        self.suspension = suspension
        self.startedAt = startedAt
        self.metadata = metadata
    }

    public var interactionRequest: AgentInteraction.Request {
        .init(
            sessionID: sessionID,
            suspension: suspension
        )
    }
}

public enum AgentProgramReplayError:
    Error,
    Sendable,
    LocalizedError
{
    case tool_resume_unsupported(AgentToolIdentifier)
    case program_mismatch(
        expected: AgentProgramIdentifier,
        actual: AgentProgramIdentifier
    )
    case program_version_mismatch(
        expected: String?,
        actual: String?
    )
    case step_mismatch(index: Int)

    public var errorDescription: String? {
        switch self {
        case .tool_resume_unsupported(let identifier):
            return "Program tool '\(identifier.rawValue)' does not support approval resume."

        case .program_mismatch(let expected, let actual):
            return "Program checkpoint belongs to '\(expected.rawValue)', not '\(actual.rawValue)'."

        case .program_version_mismatch(let expected, let actual):
            return "Program checkpoint version '\(expected ?? "<none>")' does not match '\(actual ?? "<none>")'."

        case .step_mismatch(let index):
            return "Program replay diverged from the recorded semantic step at index \(index)."
        }
    }
}
