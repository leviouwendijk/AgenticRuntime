import Agentic
import AgenticExecution
import AgenticPrograms
import Foundation
import Primitives

/// Durable continuation material for an AgentProgram that reaches an
/// interaction boundary.
///
/// This is the persisted representation. Executable resume state is constructed
/// through AgentProgramCheckpoint.Resume<Program>'s throwing initializer.
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

public extension AgentProgramCheckpoint {
    struct Resume<Program: AgentProgram>: Sendable {
        public let sessionID: String
        public let input: Program.Input
        public let realization: AgentProgramRealization<Program>?
        public let completedSteps: [AgentProgramStepRecord]
        public let suspendedStep: AgentProgramStepRecord
        public let pendingApproval: PendingApproval
        public let decision: ApprovalDecision
        public let startedAt: Date
        public let metadata: [String: String]

        public init(
            checkpoint: AgentProgramCheckpoint,
            response: AgentInteraction.Response
        ) throws {
            guard checkpoint.programIdentifier
                    == Program.descriptor.identifier
            else {
                throw AgentProgramReplayError.program_mismatch(
                    expected: checkpoint.programIdentifier,
                    actual: Program.descriptor.identifier
                )
            }

            guard checkpoint.programVersion
                    == Program.descriptor.version
            else {
                throw AgentProgramReplayError
                    .program_version_mismatch(
                        expected: checkpoint.programVersion,
                        actual: Program.descriptor.version
                    )
            }

            for (expectedIndex, step) in
                checkpoint.completedSteps.enumerated()
            {
                guard step.index == expectedIndex,
                      step.output != nil,
                      step.suspension == nil,
                      step.failure == nil
                else {
                    throw AgentProgramReplayError
                        .invalid_completed_step(
                            index: expectedIndex
                        )
                }
            }

            guard checkpoint.suspendedStep.index
                    == checkpoint.completedSteps.count,
                  checkpoint.suspendedStep.output == nil,
                  checkpoint.suspendedStep.failure == nil,
                  checkpoint.suspendedStep.suspension
                    == checkpoint.suspension
            else {
                throw AgentProgramReplayError.step_mismatch(
                    index: checkpoint.suspendedStep.index
                )
            }

            guard case .tool(let toolIdentifier) =
                    checkpoint.suspendedStep.kind,
                  let pendingApproval =
                    checkpoint.suspension.reason.pendingApproval,
                  pendingApproval.requirement
                    == .needs_human_review,
                  pendingApproval.toolCall.name
                    == toolIdentifier.rawValue,
                  pendingApproval.toolCall.input
                    == checkpoint.suspendedStep.input
            else {
                throw AgentProgramReplayError
                    .invalid_suspension
            }

            guard response.sessionID == checkpoint.sessionID else {
                throw AgentInteractionError.sessionMismatch(
                    expected: checkpoint.sessionID,
                    received: response.sessionID
                )
            }

            guard response.requestID
                    == checkpoint.suspension.id
            else {
                throw AgentInteractionError.requestMismatch(
                    expected: checkpoint.suspension.id,
                    received: response.requestID
                )
            }

            guard case .approval(let decision) =
                    response.resolution
            else {
                throw AgentInteractionError.resolutionMismatch(
                    expected: .approval,
                    received: response.kind
                )
            }

            let input = try JSONToolBridge.decode(
                Program.Input.self,
                from: checkpoint.input
            )
            let realization: AgentProgramRealization<Program>?

            if let value = checkpoint.realization {
                realization = try JSONToolBridge.decode(
                    AgentProgramRealization<Program>.self,
                    from: value
                )
            } else {
                realization = nil
            }

            self.sessionID = checkpoint.sessionID
            self.input = input
            self.realization = realization
            self.completedSteps = checkpoint.completedSteps
            self.suspendedStep = checkpoint.suspendedStep
            self.pendingApproval = pendingApproval
            self.decision = decision
            self.startedAt = checkpoint.startedAt
            self.metadata = checkpoint.metadata.merging(
                response.metadata
            ) { _, new in
                new
            }
        }
    }
}

public enum AgentProgramReplayError:
    Error,
    Sendable,
    LocalizedError
{
    case tool_resume_unsupported(AgentToolIdentifier)
    case nested_program_suspension_unsupported(
        AgentProgramIdentifier
    )
    case program_mismatch(
        expected: AgentProgramIdentifier,
        actual: AgentProgramIdentifier
    )
    case program_version_mismatch(
        expected: String?,
        actual: String?
    )
    case invalid_completed_step(index: Int)
    case invalid_suspension
    case step_mismatch(index: Int)
    case suspended_step_not_consumed(index: Int)

    public var errorDescription: String? {
        switch self {
        case .tool_resume_unsupported(let identifier):
            return "Program tool '\(identifier.rawValue)' does not support approval resume."

        case .nested_program_suspension_unsupported(let identifier):
            return "Nested Program '\(identifier.rawValue)' reached a suspension boundary that direct Program replay does not yet support."

        case .program_mismatch(let expected, let actual):
            return "Program checkpoint belongs to '\(expected.rawValue)', not '\(actual.rawValue)'."

        case .program_version_mismatch(let expected, let actual):
            return "Program checkpoint version '\(expected ?? "<none>")' does not match '\(actual ?? "<none>")'."

        case .invalid_completed_step(let index):
            return "Program checkpoint contains a non-replayable completed step at index \(index)."

        case .invalid_suspension:
            return "Program checkpoint does not contain a resumable approval suspension."

        case .step_mismatch(let index):
            return "Program replay diverged from the recorded semantic step at index \(index)."

        case .suspended_step_not_consumed(let index):
            return "Program replay completed without revisiting suspended step \(index)."
        }
    }
}

struct AgentProgramSuspensionSignal:
    Error,
    Sendable
{
    let suspension: AgentSuspension
}

struct AgentProgramResumeResolution:
    Sendable
{
    let pendingApproval: PendingApproval
    let decision: ApprovalDecision
}

actor AgentProgramResumeControl {
    private let expectedStep: AgentProgramStepRecord
    private let pendingApproval: PendingApproval
    private let decision: ApprovalDecision
    private var consumed = false

    init<Program: AgentProgram>(
        resume: AgentProgramCheckpoint.Resume<Program>
    ) {
        self.expectedStep = resume.suspendedStep
        self.pendingApproval = resume.pendingApproval
        self.decision = resume.decision
    }

    func resolution(
        at index: Int,
        identifier: AgentToolIdentifier,
        input: JSONValue
    ) throws -> AgentProgramResumeResolution? {
        if index < expectedStep.index {
            return nil
        }

        if index > expectedStep.index {
            guard consumed else {
                throw AgentProgramReplayError.step_mismatch(
                    index: index
                )
            }

            return nil
        }

        guard !consumed,
              expectedStep.kind == .tool(identifier),
              expectedStep.input == input,
              pendingApproval.toolCall.name
                == identifier.rawValue,
              pendingApproval.toolCall.input == input
        else {
            throw AgentProgramReplayError.step_mismatch(
                index: index
            )
        }

        consumed = true

        return .init(
            pendingApproval: pendingApproval,
            decision: decision
        )
    }

    func requireConsumed() throws {
        guard consumed else {
            throw AgentProgramReplayError
                .suspended_step_not_consumed(
                    index: expectedStep.index
                )
        }
    }
}
