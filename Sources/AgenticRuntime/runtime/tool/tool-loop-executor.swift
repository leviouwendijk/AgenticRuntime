import Agentic
import AgenticExecution
import AgenticUsage
import AgenticWorkspace
import Foundation

public struct ToolLoopExecutor: Sendable {
    public let adapter: any AgentModelAdapter
    public let configuration: AgentRunnerConfiguration
    public let toolRegistry: ToolRegistry
    public let extensions: [any AgentHarnessExtension]
    public let workspace: AgentWorkspace?
    public let approvalHandler: (any ToolApprovalHandler)?
    public let historyStore: (any AgentHistoryStore)?
    public let eventSinks: [any AgentRunEventSink]
    public let costTracker: AgentCostTracker?

    public init(
        adapter: any AgentModelAdapter,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        workspace: AgentWorkspace? = nil,
        approvalHandler: (any ToolApprovalHandler)? = nil,
        historyStore: (any AgentHistoryStore)? = nil,
        eventSinks: [any AgentRunEventSink] = [],
        costTracker: AgentCostTracker? = nil
    ) {
        self.adapter = adapter
        self.configuration = configuration
        self.toolRegistry = toolRegistry
        self.extensions = extensions
        self.workspace = workspace
        self.approvalHandler = approvalHandler
        self.historyStore = historyStore
        self.eventSinks = eventSinks
        self.costTracker = costTracker
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
