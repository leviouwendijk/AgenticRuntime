import Agentic
import AgenticInference
import AgenticPrograms
import AgenticRecovery
import Foundation
import Primitives

public enum AgentProgramExecutionOutcome:
    String,
    Sendable,
    Codable,
    Hashable
{
    case succeeded
    case suspended
    case failed
}

public enum AgentProgramStepKind:
    Sendable,
    Codable,
    Hashable
{
    case inference(
        site: AgentInferenceSiteIdentifier,
        inference: AgentInferenceIdentifier
    )
    case tool(AgentToolIdentifier)
    case user_input
    case program(AgentProgramIdentifier)
}

public struct AgentProgramFailureRecord:
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

public struct AgentProgramStepRecord:
    Sendable,
    Codable,
    Hashable
{
    public struct Inference:
        Sendable,
        Codable,
        Hashable
    {
        public var realization: AgentInferenceRealization?
        public var execution: AgentInferenceExecutionRecord?

        public init(
            realization: AgentInferenceRealization? = nil,
            execution: AgentInferenceExecutionRecord? = nil
        ) {
            self.realization = realization
            self.execution = execution
        }
    }

    public var index: Int
    public var kind: AgentProgramStepKind
    public var input: JSONValue
    public var output: JSONValue?
    public var inference: Inference
    public var recovery: Recovery.Record?
    public var suspension: AgentSuspension?
    public var failure: AgentProgramFailureRecord?
    public var startedAt: Date
    public var completedAt: Date
    public var durationMilliseconds: Int
    public var metadata: [String: String]

    public init(
        index: Int,
        kind: AgentProgramStepKind,
        input: JSONValue,
        output: JSONValue? = nil,
        inference: Inference = .init(),
        recovery: Recovery.Record? = nil,
        suspension: AgentSuspension? = nil,
        failure: AgentProgramFailureRecord? = nil,
        startedAt: Date,
        completedAt: Date,
        durationMilliseconds: Int,
        metadata: [String: String] = [:]
    ) {
        self.index = index
        self.kind = kind
        self.input = input
        self.output = output
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

public struct AgentProgramExecutionRecord:
    Sendable,
    Codable,
    Hashable
{
    public var sessionID: String?
    public var programIdentifier: AgentProgramIdentifier
    public var programVersion: String?
    public var realizationIdentifier: AgentProgramRealizationIdentifier?
    public var input: JSONValue
    public var output: JSONValue?
    public var steps: [AgentProgramStepRecord]
    public var outcome: AgentProgramExecutionOutcome
    public var suspension: AgentSuspension?
    public var checkpoint: AgentProgramCheckpoint?
    public var failure: AgentProgramFailureRecord?
    public var startedAt: Date
    public var completedAt: Date
    public var durationMilliseconds: Int
    public var metadata: [String: String]

    public init(
        sessionID: String? = nil,
        programIdentifier: AgentProgramIdentifier,
        programVersion: String? = nil,
        realizationIdentifier: AgentProgramRealizationIdentifier? = nil,
        input: JSONValue,
        output: JSONValue? = nil,
        steps: [AgentProgramStepRecord] = [],
        outcome: AgentProgramExecutionOutcome,
        suspension: AgentSuspension? = nil,
        checkpoint: AgentProgramCheckpoint? = nil,
        failure: AgentProgramFailureRecord? = nil,
        startedAt: Date,
        completedAt: Date,
        durationMilliseconds: Int,
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.programIdentifier = programIdentifier
        self.programVersion = programVersion
        self.realizationIdentifier = realizationIdentifier
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

    public var interactionRequest: AgentInteraction.Request? {
        checkpoint?.interactionRequest
    }
}

public struct AgentProgramExecution<Program: AgentProgram>:
    Sendable
{
    public var output: Program.Output?
    public var record: AgentProgramExecutionRecord

    public init(
        output: Program.Output?,
        record: AgentProgramExecutionRecord
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

    public var interactionRequest: AgentInteraction.Request? {
        record.interactionRequest
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
