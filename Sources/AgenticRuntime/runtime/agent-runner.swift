import Agentic
import AgenticExecution
import AgenticModels
import AgenticTools
import AgenticUsage
import AgenticWorkspace
import Foundation

public actor AgentRunner {
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
        let executor = try await makeToolLoopExecutor()

        return try await executor.run(
            request,
            sessionID: sessionID
        )
    }

    public func resume(
        sessionID: String
    ) async throws -> AgentRunResult {
        guard let historyStore else {
            throw AgentHistoryError.historyStoreRequired
        }

        guard let checkpoint = try await historyStore.loadCheckpoint(
            sessionID: sessionID
        ) else {
            throw AgentHistoryError.checkpointNotFound(
                sessionID
            )
        }

        switch checkpoint.phase {
        case .suspended,
             .awaiting_approval:
            return try suspendedResult(
                from: checkpoint
            )

        case .completed:
            guard let response = checkpoint.lastResponse else {
                throw AgentHistoryError.corruptedCheckpoint(
                    "completed checkpoint without final response"
                )
            }

            return .completed(
                sessionID: checkpoint.id,
                response: response,
                state: checkpoint.state,
                events: checkpoint.events,
                costRecord: checkpoint.costRecord
            )

        case .ready_for_model,
             .processing_tool_calls:
            let executor = try await makeToolLoopExecutor(
                restoring: checkpoint
            )

            return try await executor.resume(
                checkpoint
            )

        case .receiving_model_response:
            throw AgentStreamingError.receivingModelResponseCheckpoint(
                checkpoint.id
            )

        case .interrupted:
            throw AgentStreamingError.interruptedCheckpoint(
                checkpoint.id
            )

        case .failed:
            guard let failure = checkpoint.failure else {
                throw AgentStreamingError.failedCheckpoint(
                    checkpoint.id
                )
            }

            return .failed(
                sessionID: checkpoint.id,
                failure: failure,
                response: checkpoint.lastResponse,
                state: checkpoint.state,
                events: checkpoint.events,
                costRecord: checkpoint.costRecord
            )
        }
    }

    public func resume(
        sessionID: String,
        userInput: String,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        try await resume(
            sessionID: sessionID,
            answer: .text(
                userInput
            ),
            metadata: metadata
        )
    }

    public func resume(
        sessionID: String,
        answer: UserInputAnswer,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        guard let historyStore else {
            throw AgentHistoryError.historyStoreRequired
        }

        guard let checkpoint = try await historyStore.loadCheckpoint(
            sessionID: sessionID
        ) else {
            throw AgentHistoryError.checkpointNotFound(
                sessionID
            )
        }

        let executor = try await makeToolLoopExecutor(
            restoring: checkpoint
        )

        return try await executor.resume(
            checkpoint,
            answer: answer,
            metadata: metadata
        )
    }
}

extension AgentRunner {
    func makeToolLoopExecutor(
        restoring checkpoint: AgentHistoryCheckpoint? = nil
    ) async throws -> ToolLoopExecutor {
        let exposure = AgentToolExposure(
            policy: configuration.toolExposure.resolvedForRuntime
        )
        var registry = toolRegistry

        if configuration.toolExposure.usesDiscovery,
           registry.registeredTool(
               identifiedBy: FindToolsTool.identifier
           ) == nil {
            try registry.register(
                FindToolsTool(
                    registry: toolRegistry,
                    exposure: exposure
                )
            )
        }

        if configuration.toolExposure.usesDiscovery,
           let identifiers = checkpoint?.exposedToolIdentifiers {
            _ = try await exposure.activate(
                identifiers,
                in: registry
            )
        }

        return ToolLoopExecutor(
            adapter: adapter,
            configuration: configuration,
            toolRegistry: registry,
            toolExposure: exposure,
            extensions: extensions,
            workspace: workspace,
            approvalHandler: approvalHandler,
            historyStore: historyStore,
            eventSinks: eventSinks,
            costTracker: costTracker
        )
    }

    func suspendedResult(
        from checkpoint: AgentHistoryCheckpoint
    ) throws -> AgentRunResult {
        guard let response = checkpoint.lastResponse else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without last response"
            )
        }

        guard let suspension = checkpoint.resolvedSuspension else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without suspension payload"
            )
        }

        switch suspension.reason {
        case .approval(let pendingApproval):
            return .awaitingApproval(
                sessionID: checkpoint.id,
                response: response,
                pendingApproval: pendingApproval,
                state: checkpoint.state,
                events: checkpoint.events,
                costRecord: checkpoint.costRecord
            )

        case .user_input(let pendingUserInput):
            return .awaitingUserInput(
                sessionID: checkpoint.id,
                response: response,
                pendingUserInput: pendingUserInput,
                state: checkpoint.state,
                events: checkpoint.events,
                costRecord: checkpoint.costRecord
            )
        }
    }
}

public extension AgentRunner {
    init(
        modelBroker: AgentModelBroker,
        modeApplication: ModeRuntimeApplication,
        extensions: [any AgentHarnessExtension] = [],
        workspace: AgentWorkspace? = nil,
        approvalHandler: (any ToolApprovalHandler)? = nil,
        historyStore: (any AgentHistoryStore)? = nil,
        eventSinks: [any AgentRunEventSink] = [],
        costTracker: AgentCostTracker? = nil
    ) {
        self.init(
            modelBroker: modelBroker,
            routePolicy: modeApplication.routePolicy,
            configuration: modeApplication.configuration,
            toolRegistry: modeApplication.toolRegistry,
            extensions: extensions,
            workspace: workspace,
            approvalHandler: approvalHandler,
            historyStore: historyStore,
            eventSinks: eventSinks,
            costTracker: costTracker
        )
    }

    init(
        modelBroker: AgentModelBroker,
        environment: AgentRuntimeEnvironment,
        sessionID: String,
        modeApplication: ModeRuntimeApplication,
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        costTracker: AgentCostTracker? = nil,
        enableHistoryPersistence: Bool = true
    ) throws {
        try self.init(
            modelBroker: modelBroker,
            environment: environment,
            sessionID: sessionID,
            routePolicy: modeApplication.routePolicy,
            configuration: modeApplication.configuration,
            toolRegistry: modeApplication.toolRegistry,
            extensions: extensions,
            approvalHandler: approvalHandler,
            costTracker: costTracker,
            enableHistoryPersistence: enableHistoryPersistence
        )
    }
}
