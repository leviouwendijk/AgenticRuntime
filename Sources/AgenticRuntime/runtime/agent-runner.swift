import Agentic
import AgenticUsage
import Workspace
import Foundation

public actor AgentRunner {
    public let model: RuntimeServices.Model
    public let configuration: AgentRunner.Configuration
    public let tooling: RuntimeServices.Tooling
    /// The inventory owns the only live capability authority for this runner.
    public let capabilities: CapabilityInventory

    public var capabilityState: AgentCapabilityState {
        capabilities.state
    }
    public let runControl: Run.Control
    public let extensions: [any AgentHarnessExtension]
    public let recording: RuntimeServices.Recording
    public let contextServices: Context.Services?
    private var contextAllocators: [String: Context.Allocator] = [:]

    /// An installed-capability inventory is the single source of live authority.
    /// Callers cannot inject an unrelated capability state beside it.
    public init(
        model: RuntimeServices.Model,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        inventory: CapabilityInventory,
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        contextServices: Context.Services? = nil
    ) {
        self.model = model
        self.configuration = configuration
        self.tooling = tooling
        self.capabilities = inventory
        self.runControl = Run.Control()
        self.extensions = extensions
        self.recording = recording
        self.contextServices = contextServices
    }

    /// Tool-only callers may supply their capability state directly; the
    /// inventory is constructed once and thereafter owns that state.
    public init(
        model: RuntimeServices.Model,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        capabilityState: AgentCapabilityState,
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        contextServices: Context.Services? = nil
    ) {
        self.init(
            model: model,
            configuration: configuration,
            tooling: tooling,
            inventory: CapabilityInventory(
                tools: tooling.registry,
                catalog: tooling.catalog,
                state: capabilityState
            ),
            extensions: extensions,
            recording: recording,
            contextServices: contextServices
        )
    }

    public func run(
        _ request: AgentRequest,
        sessionID: String = UUID().uuidString
    ) async throws -> AgentRunner.Result {
        let executor = try await makeAgentLoop(sessionID: sessionID)

        return try await executor.run(
            request,
            sessionID: sessionID
        )
    }

    public func resume(
        sessionID: String
    ) async throws -> AgentRunner.Result {
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
            let executor = try await makeAgentLoop(
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
    ) async throws -> AgentRunner.Result {
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
    ) async throws -> AgentRunner.Result {
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
    ) async throws -> AgentRunner.Result {
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

        let executor = try await makeAgentLoop(
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
    func makeAgentLoop(
        restoring checkpoint: AgentRunner.Checkpoint? = nil,
        sessionID: String? = nil
    ) async throws -> AgentLoop {
        if let checkpoint {
            guard checkpoint.contextMode == configuration.contextMode else {
                throw ContextExecutionError.checkpointModeChanged
            }
            guard checkpoint.contextPolicy == configuration.contextPolicy else {
                throw ContextExecutionError.checkpointPolicyChanged
            }
            _ = await capabilities.state.restore(checkpoint.capabilities)
        }
        if configuration.contextMode == .dynamic,
           configuration.compactionStrategy != nil {
            throw ContextExecutionError.incompatibleCompaction
        }
        let identity = checkpoint?.id ?? sessionID
        let contextAllocator: Context.Allocator?
        if configuration.contextMode == .dynamic, let identity {
            contextAllocator = try await contextAllocatorForSession(
                identity,
                restoring: checkpoint?.contextWorkingSet,
                transitions: checkpoint?.contextTransitions ?? []
            )
        } else {
            contextAllocator = nil
        }

        return AgentLoop(
            model: model,
            configuration: configuration,
            tooling: tooling,
            inventory: capabilities,
            runControl: runControl,
            extensions: extensions,
            recording: recording,
            contextAllocator: contextAllocator,
            contextServices: contextServices
        )
    }

    private func contextAllocatorForSession(
        _ sessionID: String,
        restoring saved: Context.WorkingSet?,
        transitions: [Context.Transition]
    ) async throws -> Context.Allocator {
        if let previous = contextAllocators[sessionID] {
            return previous
        }
        let allocator = try Context.Allocator(policy: configuration.contextPolicy)
        if let saved {
            guard saved.id == sessionID else {
                throw ContextAllocatorError.unknownWorkingSet(saved.id)
            }
            try await allocator.restore(saved, transitions: transitions)
        } else {
            try await allocator.createWorkingSet(id: sessionID)
        }
        contextAllocators[sessionID] = allocator
        return allocator
    }

    /// Trusted host API. This is not a model-callable capability or a source grant.
    public func contextAllocator(for sessionID: String) async throws -> Context.Allocator {
        guard configuration.contextMode == .dynamic else {
            throw ContextExecutionError.requiresDynamicMode
        }
        return try await contextAllocatorForSession(sessionID, restoring: nil, transitions: [])
    }

    func suspendedResult(
        from checkpoint: AgentRunner.Checkpoint
    ) throws -> AgentRunner.Result {
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
        model: RuntimeServices.Model,
        modeApplication: ModeRuntimeApplication,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init()
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
        model: RuntimeServices.Model,
        environment: AgentRuntimeEnvironment,
        sessionID: String,
        modeApplication: ModeRuntimeApplication,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
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
