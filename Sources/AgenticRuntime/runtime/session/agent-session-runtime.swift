import Agentic
import AgenticSessions
import Foundation

public struct AgentSessionRuntime: Sendable {
    public let sessionID: String
    public let environment: AgentRuntimeEnvironment
    public let stores: AgentRuntimeStores
    public let metadata: Sessions.Metadata

    public init(
        sessionID: String = UUID().uuidString,
        environment: AgentRuntimeEnvironment,
        stores: AgentRuntimeStores,
        metadata: Sessions.Metadata? = nil
    ) {
        self.sessionID = sessionID
        self.environment = environment
        self.stores = stores
        self.metadata = metadata ?? .init(
            sessionID: sessionID,
            workspaceAttached: environment.workspace != nil
        )
    }

    public static func resolve(
        sessionID: String = UUID().uuidString,
        environment: AgentRuntimeEnvironment,
        metadata: Sessions.Metadata? = nil
    ) throws -> Self {
        let stores = try AgentRuntimeStoreResolver(
            environment: environment
        ).resolveStores(
            sessionID: sessionID
        )

        let resolvedMetadata = try resolveMetadata(
            sessionID: sessionID,
            environment: environment,
            stores: stores,
            metadata: metadata
        )

        return .init(
            sessionID: sessionID,
            environment: environment,
            stores: stores,
            metadata: resolvedMetadata
        )
    }

    public func branch(
        sessionID: String = UUID().uuidString,
        branchedAtEventID: String? = nil,
        branchedAtCheckpointID: String? = nil,
        note: String? = nil,
        title: String? = nil,
        metadata extraMetadata: [String: String] = [:]
    ) async throws -> AgentSessionRuntime {
        let branch = SessionBranch(
            parentSessionID: self.sessionID,
            branchedAtEventID: branchedAtEventID,
            branchedAtCheckpointID: branchedAtCheckpointID,
            note: note
        )

        let branchMetadata = Sessions.Metadata(
            sessionID: sessionID,
            title: title,
            status: .active,
            workspaceAttached: environment.workspace != nil,
            branch: branch,
            metadata: extraMetadata
        )

        let runtime = try Self.resolve(
            sessionID: sessionID,
            environment: environment,
            metadata: branchMetadata
        )

        try await runtime.recordSessionBranch(
            branch
        )

        return runtime
    }

    public func makeExecutor(
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        capabilityState: AgentCapabilityState,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        enableHistoryPersistence: Bool = true
    ) throws -> AgentExecutor {
        var resolvedConfiguration = configuration

        if enableHistoryPersistence,
           stores.historyStore != nil,
           resolvedConfiguration.historyPersistenceMode == .disabled {
            resolvedConfiguration.historyPersistenceMode = .checkpointmutation
        }

        return AgentExecutor(
            model: model,
            configuration: resolvedConfiguration,
            tooling: tooling.using(
                workspace: try environment.workspace?.context(execution: environment.workspaceExecution)
            ),
            capabilityState: capabilityState,
            extensions: extensions,
            recording: recording.resolving(
                historyStore: stores.historyStore,
                eventSinks: stores.eventSinks
            )
        )
    }

    public func run(
        _ request: AgentRequest,
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        capabilityState: AgentCapabilityState,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        enableHistoryPersistence: Bool = true
    ) async throws -> AgentExecutor.Result {
        try saveMetadata(
            metadata.withStatus(
                .active
            )
        )

        let executor = try makeExecutor(
            model: model,
            configuration: configuration,
            capabilityState: capabilityState,
            tooling: tooling,
            extensions: extensions,
            recording: recording,
            enableHistoryPersistence: enableHistoryPersistence
        )

        let result = try await executor.run(
            request,
            sessionID: sessionID
        )

        try saveMetadata(
            metadata.withStatus(
                status(
                    for: result
                )
            )
        )

        return result
    }

    public func resume(
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        capabilityState: AgentCapabilityState,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        enableHistoryPersistence: Bool = true
    ) async throws -> AgentExecutor.Result {
        try saveMetadata(
            metadata.withStatus(
                .active
            )
        )

        let executor = try makeExecutor(
            model: model,
            configuration: configuration,
            capabilityState: capabilityState,
            tooling: tooling,
            extensions: extensions,
            recording: recording,
            enableHistoryPersistence: enableHistoryPersistence
        )

        let result = try await executor.resume(
            sessionID: sessionID
        )

        try saveMetadata(
            metadata.withStatus(
                status(
                    for: result
                )
            )
        )

        return result
    }

    public func resume(
        userInput: String,
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        capabilityState: AgentCapabilityState,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        enableHistoryPersistence: Bool = true,
        metadata: [String: String] = [:]
    ) async throws -> AgentExecutor.Result {
        try await resume(
            answer: .text(
                userInput
            ),
            model: model,
            configuration: configuration,
            capabilityState: capabilityState,
            tooling: tooling,
            extensions: extensions,
            recording: recording,
            enableHistoryPersistence: enableHistoryPersistence,
            metadata: metadata
        )
    }

    public func resume(
        answer: UserInputAnswer,
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        capabilityState: AgentCapabilityState,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        enableHistoryPersistence: Bool = true,
        metadata: [String: String] = [:]
    ) async throws -> AgentExecutor.Result {
        try await resume(
            reply: .answer(
                answer
            ),
            model: model,
            configuration: configuration,
            capabilityState: capabilityState,
            tooling: tooling,
            extensions: extensions,
            recording: recording,
            enableHistoryPersistence: enableHistoryPersistence,
            metadata: metadata
        )
    }

    public func resume(
        reply: UserInputReply,
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        capabilityState: AgentCapabilityState,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        enableHistoryPersistence: Bool = true,
        metadata: [String: String] = [:]
    ) async throws -> AgentExecutor.Result {
        try saveMetadata(
            self.metadata.withStatus(
                .active
            )
        )

        let executor = try makeExecutor(
            model: model,
            configuration: configuration,
            capabilityState: capabilityState,
            tooling: tooling,
            extensions: extensions,
            recording: recording,
            enableHistoryPersistence: enableHistoryPersistence
        )

        let result = try await executor.resume(
            sessionID: sessionID,
            reply: reply,
            metadata: metadata
        )

        try saveMetadata(
            self.metadata.withStatus(
                status(
                    for: result
                )
            )
        )

        return result
    }
}

private extension AgentSessionRuntime {
    static func resolveMetadata(
        sessionID: String,
        environment: AgentRuntimeEnvironment,
        stores: AgentRuntimeStores,
        metadata: Sessions.Metadata?
    ) throws -> Sessions.Metadata {
        if let metadata {
            let resolved = metadata
                .withSessionID(sessionID)
                .touching()

            try stores.sessionMetadataStore?.save(
                resolved
            )

            return resolved
        }

        if let existing = try stores.sessionMetadataStore?.load(
            sessionID: sessionID
        ) {
            let resolved = existing.touching()

            try stores.sessionMetadataStore?.save(
                resolved
            )

            return resolved
        }

        let created = Sessions.Metadata(
            sessionID: sessionID,
            workspaceAttached: environment.workspace != nil
        )

        try stores.sessionMetadataStore?.save(
            created
        )

        return created
    }

    func saveMetadata(
        _ metadata: Sessions.Metadata
    ) throws {
        try stores.sessionMetadataStore?.save(
            metadata.withSessionID(
                sessionID
            )
        )
    }

    func recordSessionBranch(
        _ branch: SessionBranch
    ) async throws {
        let event = SessionBranchEvent(
            sessionID: sessionID,
            branch: branch
        )

        for sink in stores.eventSinks {
            try await sink.recordSessionBranch(
                event
            )
        }
    }

    func status(
        for result: AgentExecutor.Result
    ) -> Sessions.Status {
        if result.isAwaitingApproval {
            return .awaiting_approval
        }

        if result.isAwaitingUserInput {
            return .awaiting_user_input
        }

        if result.isCompleted {
            return .completed
        }

        return .active
    }
}

