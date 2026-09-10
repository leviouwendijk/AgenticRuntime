import Agentic
import AgenticExecution
import AgenticUsage
import AgenticWorkspace
import Foundation

public struct ToolLoopExecutor: Sendable {
    public let model: AgentRuntimeServices.Model
    public let configuration: AgentRunnerConfiguration
    public let tooling: AgentRuntimeServices.Tooling
    public let toolExposure: AgentToolExposure
    public let extensions: [any AgentHarnessExtension]
    public let recording: AgentRuntimeServices.Recording

    public init(
        model: AgentRuntimeServices.Model,
        configuration: AgentRunnerConfiguration = .default,
        tooling: AgentRuntimeServices.Tooling = .init(),
        toolExposure: AgentToolExposure = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: AgentRuntimeServices.Recording = .init()
    ) {
        self.model = model
        self.configuration = configuration
        self.tooling = tooling
        self.toolExposure = toolExposure
        self.extensions = extensions
        self.recording = recording
    }

    public func run(
        _ request: AgentRequest,
        sessionID: String = UUID().uuidString
    ) async throws -> AgentRunResult {
        var checkpoint = AgentHistoryCheckpoint(
            id: sessionID,
            originalRequest: request,
            state: .init(
                iteration: 0,
                messages: request.messages
            )
        )

        try await recordMessages(
            request.messages
        )

        try await saveCheckpoint(
            &checkpoint
        )

        return try await runLoop(
            from: checkpoint
        )
    }

    public func resume(
        _ checkpoint: AgentHistoryCheckpoint
    ) async throws -> AgentRunResult {
        try await runLoop(
            from: checkpoint
        )
    }

    public func resume(
        _ checkpoint: AgentHistoryCheckpoint,
        userInput: String,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        try await resumeWithUserInput(
            checkpoint,
            userInput: userInput,
            metadata: metadata
        )
    }

    public func resume(
        _ checkpoint: AgentHistoryCheckpoint,
        answer: UserInputAnswer,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        try await resumeWithUserInput(
            checkpoint,
            answer: answer,
            metadata: metadata
        )
    }
}

extension ToolLoopExecutor {
    struct ToolDenialPayload: Encodable, Sendable {
        let kind: String
        let toolCallID: String
        let toolName: String
        let requirement: String
        let summary: String
    }

    struct ToolErrorPayload: Encodable, Sendable {
        let kind: String
        let toolCallID: String
        let toolName: String
        let message: String
    }

    struct ToolSkipPayload: Encodable, Sendable {
        let kind: String
        let toolCallID: String
        let toolName: String
        let summary: String
    }

    struct UserInputResumePayload: Encodable, Sendable {
        let kind: String
        let prompt: String
        let answer: UserInputAnswer
        let metadata: [String: String]
    }

    enum ToolProcessingOutcome {
        case continueLoop(AgentHistoryCheckpoint)
        case result(AgentRunResult)
    }
}
