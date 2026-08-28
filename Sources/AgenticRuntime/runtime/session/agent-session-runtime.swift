import Agentic
import AgenticExecution
import AgenticTools
import Foundation

public struct AgentSessionRuntime: Sendable {
    public let sessionID: String
    public let environment: AgentRuntimeEnvironment
    public let stores: AgentRuntimeStores
    public let metadata: AgentSessionMetadata

    public init(
        sessionID: String = UUID().uuidString,
        environment: AgentRuntimeEnvironment,
        stores: AgentRuntimeStores,
        metadata: AgentSessionMetadata? = nil
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
        metadata: AgentSessionMetadata? = nil
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
        let branch = AgentSessionBranch(
            parentSessionID: self.sessionID,
            branchedAtEventID: branchedAtEventID,
            branchedAtCheckpointID: branchedAtCheckpointID,
            note: note
        )

        let branchMetadata = AgentSessionMetadata(
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

    public func makeRunner(
        adapter: any AgentModelAdapter,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        enableHistoryPersistence: Bool = true
    ) throws -> AgentRunner {
        var resolvedConfiguration = configuration

        if enableHistoryPersistence,
           stores.historyStore != nil,
           resolvedConfiguration.historyPersistenceMode == .disabled {
            resolvedConfiguration.historyPersistenceMode = .checkpointmutation
        }

        return AgentRunner(
            adapter: adapter,
            configuration: resolvedConfiguration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            workspace: environment.workspace,
            approvalHandler: approvalHandler,
            historyStore: stores.historyStore,
            eventSinks: stores.eventSinks
        )
    }

    public func run(
        _ request: AgentRequest,
        adapter: any AgentModelAdapter,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        enableHistoryPersistence: Bool = true
    ) async throws -> AgentRunResult {
        try saveMetadata(
            metadata.withStatus(
                .active
            )
        )

        let runner = try makeRunner(
            adapter: adapter,
            configuration: configuration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            approvalHandler: approvalHandler,
            enableHistoryPersistence: enableHistoryPersistence
        )

        let result = try await runner.run(
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
        adapter: any AgentModelAdapter,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        enableHistoryPersistence: Bool = true
    ) async throws -> AgentRunResult {
        try saveMetadata(
            metadata.withStatus(
                .active
            )
        )

        let runner = try makeRunner(
            adapter: adapter,
            configuration: configuration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            approvalHandler: approvalHandler,
            enableHistoryPersistence: enableHistoryPersistence
        )

        let result = try await runner.resume(
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
        adapter: any AgentModelAdapter,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        enableHistoryPersistence: Bool = true,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        try await resume(
            answer: .text(
                userInput
            ),
            adapter: adapter,
            configuration: configuration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            approvalHandler: approvalHandler,
            enableHistoryPersistence: enableHistoryPersistence,
            metadata: metadata
        )
    }

    public func resume(
        answer: UserInputAnswer,
        adapter: any AgentModelAdapter,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        enableHistoryPersistence: Bool = true,
        metadata: [String: String] = [:]
    ) async throws -> AgentRunResult {
        try saveMetadata(
            self.metadata.withStatus(
                .active
            )
        )

        let runner = try makeRunner(
            adapter: adapter,
            configuration: configuration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            approvalHandler: approvalHandler,
            enableHistoryPersistence: enableHistoryPersistence
        )

        let result = try await runner.resume(
            sessionID: sessionID,
            answer: answer,
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
        metadata: AgentSessionMetadata?
    ) throws -> AgentSessionMetadata {
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

        let created = AgentSessionMetadata(
            sessionID: sessionID,
            workspaceAttached: environment.workspace != nil
        )

        try stores.sessionMetadataStore?.save(
            created
        )

        return created
    }

    func saveMetadata(
        _ metadata: AgentSessionMetadata
    ) throws {
        try stores.sessionMetadataStore?.save(
            metadata.withSessionID(
                sessionID
            )
        )
    }

    func recordSessionBranch(
        _ branch: AgentSessionBranch
    ) async throws {
        let event = AgentSessionBranchEvent(
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
        for result: AgentRunResult
    ) -> AgentSessionStatus {
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

public extension AgentSessionRuntime {
    func artifactToolSet() throws -> CoreArtifactToolSet {
        guard let artifactStore = stores.artifactStore else {
            throw AgentArtifactError.durableStorageRequired
        }

        return CoreArtifactToolSet(
            store: artifactStore
        )
    }
}

public extension AgentSessionRuntime {
    func preparedIntentManager() throws -> PreparedIntentManager {
        guard let preparedIntentStore = stores.preparedIntentStore else {
            throw PreparedIntentError.durableStorageRequired
        }

        return PreparedIntentManager(
            store: preparedIntentStore
        )
    }

    func preparedIntentOperatorToolSet() throws -> PreparedIntentOperatorToolSet {
        try PreparedIntentOperatorToolSet(
            manager: preparedIntentManager()
        )
    }
}
