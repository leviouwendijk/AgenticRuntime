import Agentic
import Foundation
import Primitives

public enum ProgramExecutionOutcome:
    String,
    Sendable,
    Codable,
    Hashable
{
    case succeeded
    case suspended
    case failed
}

public enum ProgramStepKind:
    Sendable,
    Codable,
    Hashable
{
    case inference(
        site: InferenceSiteIdentifier,
        inference: InferenceIdentifier
    )
    case tool(ToolIdentifier)
    case user_input
    case program(ProgramIdentifier)
}

public struct ProgramFailureRecord:
    Sendable,
    Codable,
    Hashable
{
    public var type: String
    public var message: String

    public init(
        type: String,
        message: String
    ) {
        self.type = type
        self.message = message
    }

    public init(
        error: any Error
    ) {
        self.type = String(
            reflecting: Swift.type(of: error)
        )

        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription
        {
            self.message = description
        } else {
            self.message = String(
                describing: error
            )
        }
    }
}

public struct ProgramStepRecord:
    Sendable,
    Codable,
    Hashable
{
    public struct Inference:
        Sendable,
        Codable,
        Hashable
    {
        public var realization: InferenceRealizationConfiguration?
        public var execution: InferenceExecutionRecord?

        public init(
            realization: InferenceRealizationConfiguration? = nil,
            execution: InferenceExecutionRecord? = nil
        ) {
            self.realization = realization
            self.execution = execution
        }
    }

    public var index: Int
    public var kind: ProgramStepKind
    public var input: JSONValue
    public var output: JSONValue?
    public var toolResult: ToolCall.Response?
    public var inference: Inference
    public var recovery: Recovery.Record?
    public var suspension: Run.Suspension?
    public var failure: ProgramFailureRecord?
    public var startedAt: Date
    public var completedAt: Date
    public var durationMilliseconds: Int
    public var metadata: [String: String]

    public init(
        index: Int,
        kind: ProgramStepKind,
        input: JSONValue,
        output: JSONValue? = nil,
        toolResult: ToolCall.Response? = nil,
        inference: Inference = .init(),
        recovery: Recovery.Record? = nil,
        suspension: Run.Suspension? = nil,
        failure: ProgramFailureRecord? = nil,
        startedAt: Date,
        completedAt: Date,
        durationMilliseconds: Int,
        metadata: [String: String] = [:]
    ) {
        self.index = index
        self.kind = kind
        self.input = input
        self.output = output
        self.toolResult = toolResult
        self.inference = inference
        self.recovery = recovery
        self.suspension = suspension
        self.failure = failure
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMilliseconds = durationMilliseconds
        self.metadata = metadata
    }
}

public struct ProgramExecutionRecord:
    Sendable,
    Codable,
    Hashable
{
    public var sessionID: String?
    public var programIdentifier: ProgramIdentifier
    public var input: JSONValue
    public var output: JSONValue?
    public var steps: [ProgramStepRecord]
    public var outcome: ProgramExecutionOutcome
    public var suspension: Run.Suspension?
    public var checkpoint: ProgramCheckpoint?
    public var failure: ProgramFailureRecord?
    public var startedAt: Date
    public var completedAt: Date
    public var durationMilliseconds: Int
    public var metadata: [String: String]

    public init(
        sessionID: String? = nil,
        programIdentifier: ProgramIdentifier,
        input: JSONValue,
        output: JSONValue? = nil,
        steps: [ProgramStepRecord] = [],
        outcome: ProgramExecutionOutcome,
        suspension: Run.Suspension? = nil,
        checkpoint: ProgramCheckpoint? = nil,
        failure: ProgramFailureRecord? = nil,
        startedAt: Date,
        completedAt: Date,
        durationMilliseconds: Int,
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.programIdentifier = programIdentifier
        self.input = input
        self.output = output
        self.steps = steps
        self.outcome = outcome
        self.suspension = suspension
        self.checkpoint = checkpoint
        self.failure = failure
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMilliseconds = durationMilliseconds
        self.metadata = metadata
    }

    public var isSuspended: Bool {
        outcome == .suspended
    }

    public var interactionRequest: Run.Interaction.Request? {
        checkpoint?.interactionRequest
    }
}

public struct ProgramExecution<ProgramType: Program>:
    Sendable
{
    public var output: ProgramType.Output?
    public var record: ProgramExecutionRecord

    public init(
        output: ProgramType.Output?,
        record: ProgramExecutionRecord
    ) {
        self.output = output
        self.record = record
    }

    public var isSucceeded: Bool {
        record.outcome == .succeeded
    }

    public var isSuspended: Bool {
        record.outcome == .suspended
    }

    public var isFailed: Bool {
        record.outcome == .failed
    }

    public var interactionRequest: Run.Interaction.Request? {
        record.interactionRequest
    }
}

extension ProgramStepRecord {
    var replayableToolFailure: ProgramToolFailure? {
        guard case .tool(let identifier) = kind,
              let toolResult,
              toolResult.call.tool == identifier,
              toolResult.isError,
              failure?.type
                == String(reflecting: ProgramToolFailure.self)
        else {
            return nil
        }

        return ProgramToolFailure(
            tool: identifier,
            result: toolResult,
            recovery: recovery
        )
    }

    var isReplayableCompletedStep: Bool {
        guard suspension == nil else {
            return false
        }

        if output != nil,
           failure == nil
        {
            return true
        }

        return replayableToolFailure != nil
    }
}

func agentProgramElapsedMilliseconds(
    from startedAt: Date,
    to completedAt: Date
) -> Int {
    max(
        0,
        Int(
            (completedAt.timeIntervalSince(startedAt) * 1_000)
                .rounded()
        )
    )
}
