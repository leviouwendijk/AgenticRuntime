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
        let interactionResolution: AgentProgramCheckpointResolution
        public let startedAt: Date
        public let metadata: [String: String]

        public var pendingApproval: PendingApproval? {
            guard case .approval(let pendingApproval, _) =
                    interactionResolution
            else {
                return nil
            }

            return pendingApproval
        }

        public var decision: ApprovalDecision? {
            guard case .approval(_, let decision) =
                    interactionResolution
            else {
                return nil
            }

            return decision
        }

        public var userInputRequest: UserInputRequest? {
            guard case .user_input(let request, _) =
                    interactionResolution
            else {
                return nil
            }

            return request
        }

        public var userInputResponse: UserInputResponse? {
            guard case .user_input(_, let response) =
                    interactionResolution
            else {
                return nil
            }

            return response
        }

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
                      step.isReplayableCompletedStep
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

            let interactionResolution: AgentProgramCheckpointResolution

            switch (
                checkpoint.suspendedStep.kind,
                checkpoint.suspension.reason
            ) {
            case (
                .tool(let toolIdentifier),
                .approval(let pendingApproval)
            ):
                guard pendingApproval.requirement
                        == .needs_human_review,
                      pendingApproval.toolCall.name
                        == toolIdentifier.rawValue,
                      pendingApproval.toolCall.input
                        == checkpoint.suspendedStep.input
                else {
                    throw AgentProgramReplayError
                        .invalid_suspension
                }

                guard case .approval(let decision) =
                        response.resolution
                else {
                    throw AgentInteractionError.resolutionMismatch(
                        expected: .approval,
                        received: response.kind
                    )
                }

                interactionResolution = .approval(
                    pendingApproval: pendingApproval,
                    decision: decision
                )

            case (
                .user_input,
                .user_input(let request)
            ):
                guard try JSONToolBridge.encode(
                    request
                ) == checkpoint.suspendedStep.input
                else {
                    throw AgentProgramReplayError
                        .invalid_suspension
                }

                guard case .user_input(let reply) =
                        response.resolution
                else {
                    throw AgentInteractionError.resolutionMismatch(
                        expected: .user_input,
                        received: response.kind
                    )
                }

                interactionResolution = .user_input(
                    request: request,
                    response: try UserInputResponse(
                        reply,
                        for: request
                    )
                )

            default:
                throw AgentProgramReplayError
                    .invalid_suspension
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
            self.interactionResolution = interactionResolution
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
            return "Program checkpoint does not contain a resumable interaction suspension."

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

enum AgentProgramCheckpointResolution:
    Sendable
{
    case approval(
        pendingApproval: PendingApproval,
        decision: ApprovalDecision
    )
    case user_input(
        request: UserInputRequest,
        response: UserInputResponse
    )
}

struct AgentProgramResumeResolution:
    Sendable
{
    let pendingApproval: PendingApproval
    let decision: ApprovalDecision
}

actor AgentProgramResumeControl {
    private let expectedStep: AgentProgramStepRecord
    private let interactionResolution: AgentProgramCheckpointResolution
    private var consumed = false

    init<Program: AgentProgram>(
        resume: AgentProgramCheckpoint.Resume<Program>
    ) {
        self.expectedStep = resume.suspendedStep
        self.interactionResolution = resume.interactionResolution
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
              case .approval(
                  let pendingApproval,
                  let decision
              ) = interactionResolution,
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

    func userInputResponse(
        at index: Int,
        request: UserInputRequest
    ) throws -> UserInputResponse? {
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

        let input = try JSONToolBridge.encode(
            request
        )

        guard !consumed,
              expectedStep.kind == .user_input,
              expectedStep.input == input,
              case .user_input(
                  let resumedRequest,
                  let response
              ) = interactionResolution,
              resumedRequest == request
        else {
            throw AgentProgramReplayError.step_mismatch(
                index: index
            )
        }

        consumed = true
        return response
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
