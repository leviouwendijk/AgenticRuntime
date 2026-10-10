import Agentic
import AgenticUsage
import Workspace
import Foundation

internal struct AgentLoop: Sendable {
    let model: RuntimeServices.Model
    let configuration: AgentRunner.Configuration
    let tooling: RuntimeServices.Tooling
    let capabilityState: AgentCapabilityState
    let inventory: CapabilityInventory
    let runControl: Run.Control
    let extensions: [any AgentHarnessExtension]
    let recording: RuntimeServices.Recording
    let contextAllocator: Context.Allocator?
    let contextServices: Context.Services?

    init(
        model: RuntimeServices.Model,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        capabilityState: AgentCapabilityState,
        inventory: CapabilityInventory,
        runControl: Run.Control = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        contextAllocator: Context.Allocator? = nil,
        contextServices: Context.Services? = nil
    ) {
        self.model = model
        self.configuration = configuration
        self.tooling = tooling
        self.capabilityState = capabilityState
        self.inventory = inventory
        self.runControl = runControl
        self.extensions = extensions
        self.recording = recording
        self.contextAllocator = contextAllocator
        self.contextServices = contextServices
    }

    func currentTools() async -> ToolRegistry {
        await inventory.tools()
    }

    func run(
        _ request: AgentRequest,
        sessionID: String = UUID().uuidString
    ) async throws -> AgentRunner.Result {
        var checkpoint = AgentRunner.Checkpoint(
            id: sessionID,
            originalRequest: request,
            state: .init(
                iteration: 0,
                messages: request.messages
            ),
            runLimits: configuration.runLimits,
            contextMode: configuration.contextMode,
            contextPolicy: configuration.contextPolicy,
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

    func resume(
        _ checkpoint: AgentRunner.Checkpoint
    ) async throws -> AgentRunner.Result {
        try await runLoop(
            from: checkpoint
        )
    }

    func resume(
        _ checkpoint: AgentRunner.Checkpoint,
        userInput: String,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunner.Result {
        try await resumeWithUserInput(
            checkpoint,
            userInput: userInput,
            metadata: metadata
        )
    }

    func resume(
        _ checkpoint: AgentRunner.Checkpoint,
        answer: UserInputAnswer,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunner.Result {
        try await resumeWithUserInput(
            checkpoint,
            reply: .answer(
                answer
            ),
            metadata: metadata
        )
    }

    func resume(
        _ checkpoint: AgentRunner.Checkpoint,
        reply: UserInputReply,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunner.Result {
        try await resumeWithUserInput(
            checkpoint,
            reply: reply,
            metadata: metadata
        )
    }

    func resume(
        _ checkpoint: AgentRunner.Checkpoint,
        workspaceAccessResolution: WorkspaceAccessResolution,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunner.Result {
        try await resumeWithWorkspaceAccess(
            checkpoint,
            resolution: workspaceAccessResolution,
            metadata: metadata
        )
    }

    func resume(
        _ checkpoint: AgentRunner.Checkpoint,
        runLimitResolution: AgentRunLimitResolution,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunner.Result {
        try await resumeFromRunLimit(
            checkpoint,
            resolution: runLimitResolution,
            metadata: metadata
        )
    }

    func resume(
        _ checkpoint: AgentRunner.Checkpoint,
        interaction response: Run.Interaction.Response
    ) async throws -> AgentRunner.Result {
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

extension AgentLoop {
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
        case continueLoop(AgentRunner.Checkpoint)
        case result(AgentRunner.Result)
    }
}
