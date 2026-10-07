import Agentic
import AgenticUsage
import Workspace
import Foundation

public struct ToolLoopExecutor: Sendable {
    public let model: AgentRuntimeServices.Model
    public let configuration: AgentRunnerConfiguration
    public let tooling: AgentRuntimeServices.Tooling
    public let capabilityState: AgentCapabilityState
    public let runControl: Run.Control
    @available(
        *,
        deprecated,
        renamed: "runControl"
    )
    public var interruptionController: Run.Control {
        runControl
    }
    public let extensions: [any AgentHarnessExtension]
    public let recording: AgentRuntimeServices.Recording

    public init(
        model: AgentRuntimeServices.Model,
        configuration: AgentRunnerConfiguration = .default,
        tooling: AgentRuntimeServices.Tooling = .init(),
        capabilityState: AgentCapabilityState,
        runControl: Run.Control = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: AgentRuntimeServices.Recording = .init()
    ) {
        self.model = model
        self.configuration = configuration
        self.tooling = tooling
        self.capabilityState = capabilityState
        self.runControl = runControl
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
            ),
            runLimits: configuration.runLimits,
            capabilities: await capabilityState.snapshot()
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
            reply: .answer(
                answer
            ),
            metadata: metadata
        )
    }

    public func resume(
        _ checkpoint: AgentHistoryCheckpoint,
        reply: UserInputReply,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        try await resumeWithUserInput(
            checkpoint,
            reply: reply,
            metadata: metadata
        )
    }

    public func resume(
        _ checkpoint: AgentHistoryCheckpoint,
        workspaceAccessResolution: WorkspaceAccessResolution,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        try await resumeWithWorkspaceAccess(
            checkpoint,
            resolution: workspaceAccessResolution,
            metadata: metadata
        )
    }

    public func resume(
        _ checkpoint: AgentHistoryCheckpoint,
        runLimitResolution: AgentRunLimitResolution,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        try await resumeFromRunLimit(
            checkpoint,
            resolution: runLimitResolution,
            metadata: metadata
        )
    }

    public func resume(
        _ checkpoint: AgentHistoryCheckpoint,
        interaction response: Run.Interaction.Response
    ) async throws -> AgentRunResult {
        guard checkpoint.id == response.sessionID else {
            throw Run.Interaction.Error.sessionMismatch(
                expected: checkpoint.id,
                received: response.sessionID
            )
        }

        guard let suspension = checkpoint.resolvedSuspension else {
            throw Run.Interaction.Error.noCurrentSuspension(
                sessionID: checkpoint.id
            )
        }

        guard suspension.id == response.requestID else {
            throw Run.Interaction.Error.requestMismatch(
                expected: suspension.id,
                received: response.requestID
            )
        }

        let expectedKind = suspension.reason.interactionKind

        guard expectedKind == response.kind else {
            throw Run.Interaction.Error.resolutionMismatch(
                expected: expectedKind,
                received: response.kind
            )
        }

        switch response.resolution {
        case .approval(let decision):
            return try await resumeApproval(
                checkpoint,
                decision: decision,
                metadata: response.metadata
            )

        case .user_input(let reply):
            return try await resumeWithUserInput(
                checkpoint,
                reply: reply,
                metadata: response.metadata
            )

        case .workspace_access(let resolution):
            return try await resumeWithWorkspaceAccess(
                checkpoint,
                resolution: resolution,
                metadata: response.metadata
            )

        case .run_limit(let resolution):
            return try await resumeFromRunLimit(
                checkpoint,
                resolution: resolution,
                metadata: response.metadata
            )
        }
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
        let reply: UserInputReply
        let metadata: [String: String]
    }

    struct WorkspaceAccessResumePayload: Encodable, Sendable {
        let kind: String
        let resolution: WorkspaceAccessResolution
        let metadata: [String: String]
    }

    enum ToolProcessingOutcome {
        case continueLoop(AgentHistoryCheckpoint)
        case result(AgentRunResult)
    }
}
