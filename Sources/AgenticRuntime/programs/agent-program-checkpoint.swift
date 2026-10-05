import Agentic
import Foundation
import Primitives

/// Durable continuation material for an Program that reaches an
/// interaction boundary.
///
/// This is the persisted representation. Executable resume state is constructed
/// through ProgramCheckpoint.Resume<Program>'s throwing initializer.
public struct ProgramCheckpoint:
    Sendable,
    Codable,
    Hashable
{
    public var sessionID: String
    public var programIdentifier: ProgramIdentifier
    public var input: JSONValue
    public var realization: JSONValue?
    public var completedSteps: [ProgramStepRecord]
    public var suspendedStep: ProgramStepRecord
    public var suspension: AgentSuspension
    public var startedAt: Date
    public var metadata: [String: String]

    public init(
        sessionID: String,
        programIdentifier: ProgramIdentifier,
        input: JSONValue,
        realization: JSONValue? = nil,
        completedSteps: [ProgramStepRecord],
        suspendedStep: ProgramStepRecord,
        suspension: AgentSuspension,
        startedAt: Date,
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.programIdentifier = programIdentifier
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

public extension ProgramCheckpoint {
    struct Resume<ProgramType: Program>: Sendable {
        public let sessionID: String
        public let input: ProgramType.Input
        public let realization: ProgramRealization<ProgramType>?
        public let completedSteps: [ProgramStepRecord]
        public let suspendedStep: ProgramStepRecord
        let interactionResolution: ProgramCheckpointResolution
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
            checkpoint: ProgramCheckpoint,
            response: AgentInteraction.Response
        ) throws {
            guard checkpoint.programIdentifier
                    == ProgramType.definition.identifier
            else {
                throw ProgramReplayError.program_mismatch(
                    expected: checkpoint.programIdentifier,
                    actual: ProgramType.definition.identifier
                )
            }

            for (expectedIndex, step) in
                checkpoint.completedSteps.enumerated()
            {
                guard step.index == expectedIndex,
                      step.isReplayableCompletedStep
                else {
                    throw ProgramReplayError
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
                throw ProgramReplayError.step_mismatch(
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

            let interactionResolution: ProgramCheckpointResolution

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
                      pendingApproval.toolCall.tool
                        == toolIdentifier,
                      pendingApproval.toolCall.input
                        == checkpoint.suspendedStep.input
                else {
                    throw ProgramReplayError
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
                guard try JSONCoding.default.value(
                    request
                ) == checkpoint.suspendedStep.input
                else {
                    throw ProgramReplayError
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
                throw ProgramReplayError
                    .invalid_suspension
            }

            let input = try JSONCoding.default.decode(
                ProgramType.Input.self,
                from: checkpoint.input
            )
            let realization: ProgramRealization<ProgramType>?

            if let value = checkpoint.realization {
                realization = try JSONCoding.default.decode(
                    ProgramRealization<ProgramType>.self,
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

public enum ProgramReplayError:
    Error,
    Sendable,
    LocalizedError
{
    case tool_resume_unsupported(ToolIdentifier)
    case nested_program_suspension_unsupported(
        ProgramIdentifier
    )
    case program_mismatch(
        expected: ProgramIdentifier,
        actual: ProgramIdentifier
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

struct ProgramSuspensionSignal:
    Error,
    Sendable
{
    let suspension: AgentSuspension
}

enum ProgramCheckpointResolution:
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

struct ProgramResumeResolution:
    Sendable
{
    let pendingApproval: PendingApproval
    let decision: ApprovalDecision
}

actor ProgramResumeControl {
    private let expectedStep: ProgramStepRecord
    private let interactionResolution: ProgramCheckpointResolution
    private var consumed = false

    init<ProgramType: Program>(
        resume: ProgramCheckpoint.Resume<ProgramType>
    ) {
        self.expectedStep = resume.suspendedStep
        self.interactionResolution = resume.interactionResolution
    }

    func resolution(
        at index: Int,
        identifier: ToolIdentifier,
        input: JSONValue
    ) throws -> ProgramResumeResolution? {
        if index < expectedStep.index {
            return nil
        }

        if index > expectedStep.index {
            guard consumed else {
                throw ProgramReplayError.step_mismatch(
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
              pendingApproval.toolCall.tool
                == identifier,
              pendingApproval.toolCall.input == input
        else {
            throw ProgramReplayError.step_mismatch(
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
                throw ProgramReplayError.step_mismatch(
                    index: index
                )
            }

            return nil
        }

        let input = try JSONCoding.default.value(
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
            throw ProgramReplayError.step_mismatch(
                index: index
            )
        }

        consumed = true
        return response
    }

    func requireConsumed() throws {
        guard consumed else {
            throw ProgramReplayError
                .suspended_step_not_consumed(
                    index: expectedStep.index
                )
        }
    }
}
