import Agentic
import AgenticUsage
import Workspace
import Foundation

public actor AgentRunner {
    public let model: AgentRuntimeServices.Model
    public let configuration: AgentRunnerConfiguration
    public let tooling: AgentRuntimeServices.Tooling
    public let capabilityState: AgentCapabilityState
    public let extensions: [any AgentHarnessExtension]
    public let recording: AgentRuntimeServices.Recording

    public init(
        model: AgentRuntimeServices.Model,
        configuration: AgentRunnerConfiguration = .default,
        tooling: AgentRuntimeServices.Tooling = .init(),
        capabilityState: AgentCapabilityState? = nil,
        extensions: [any AgentHarnessExtension] = [],
        recording: AgentRuntimeServices.Recording = .init()
    ) {
        self.model = model
        self.configuration = configuration
        self.tooling = tooling
        self.capabilityState =
            capabilityState
            ?? AgentCapabilityState(
                installed: AgentCapabilitySet(
                    tools: tooling.registry
                        .modelFacingDefinitions
                        .map(\.identifier)
                )
            )
        self.extensions = extensions
        self.recording = recording
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
        guard let historyStore = recording.historyStore else {
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
                toolUses: checkpoint.resolvedToolUses,
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
            return .interrupted(
                sessionID: checkpoint.id,
                response: checkpoint.lastResponse,
                state: checkpoint.state,
                events: checkpoint.events,
                toolUses: checkpoint.resolvedToolUses,
                costRecord: checkpoint.costRecord
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
                toolUses: checkpoint.resolvedToolUses,
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
        try await resume(
            sessionID: sessionID,
            reply: .answer(
                answer
            ),
            metadata: metadata
        )
    }

    public func resume(
        sessionID: String,
        reply: UserInputReply,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        guard let historyStore = recording.historyStore else {
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
            reply: reply,
            metadata: metadata
        )
    }
}

extension AgentRunner {
    func makeToolLoopExecutor(
        restoring checkpoint: AgentHistoryCheckpoint? = nil
    ) async throws -> ToolLoopExecutor {
        if let checkpoint {
            _ = await capabilityState.restore(
                checkpoint.capabilities
            )
        }

        return ToolLoopExecutor(
            model: model,
            configuration: configuration,
            tooling: tooling,
            capabilityState: capabilityState,
            extensions: extensions,
            recording: recording
        )
    }

    func suspendedResult(
        from checkpoint: AgentHistoryCheckpoint
    ) throws -> AgentRunResult {
        guard let suspension = checkpoint.resolvedSuspension else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without suspension payload"
            )
        }

        return .suspended(
            sessionID: checkpoint.id,
            phase: checkpoint.phase,
            response: checkpoint.lastResponse,
            suspension: suspension,
            state: checkpoint.state,
            events: checkpoint.events,
            toolUses: checkpoint.resolvedToolUses,
            costRecord: checkpoint.costRecord
        )
    }
}

public extension AgentRunner {
    init(
        model: AgentRuntimeServices.Model,
        modeApplication: ModeRuntimeApplication,
        tooling: AgentRuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: AgentRuntimeServices.Recording = .init()
    ) {
        self.init(
            model: model.selecting(
                modeApplication.modelSelection
            ),
            configuration: modeApplication.configuration,
            tooling: tooling.using(
                registry: modeApplication.toolRegistry
            ),
            capabilityState: modeApplication.capabilityState,
            extensions: extensions,
            recording: recording
        )
    }

    init(
        model: AgentRuntimeServices.Model,
        environment: AgentRuntimeEnvironment,
        sessionID: String,
        modeApplication: ModeRuntimeApplication,
        tooling: AgentRuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: AgentRuntimeServices.Recording = .init(),
        enableHistoryPersistence: Bool = true
    ) throws {
        try self.init(
            model: model.selecting(
                modeApplication.modelSelection
            ),
            environment: environment,
            sessionID: sessionID,
            configuration: modeApplication.configuration,
            tooling: tooling.using(
                registry: modeApplication.toolRegistry
            ),
            capabilityState: modeApplication.capabilityState,
            extensions: extensions,
            recording: recording,
            enableHistoryPersistence: enableHistoryPersistence
        )
    }
}
