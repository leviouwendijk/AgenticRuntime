import Agentic
import AgenticExecution
import AgenticUsage
import AgenticWorkspace
import Foundation

public extension Agentic {
    struct RuntimeBootstrapAPI: Sendable {
        public init() {}

        public func environment(
            explicitHome: AgentHome? = nil,
            explicitHomeRootURL: URL? = nil,
            explicitWorkspace: AgentWorkspace? = nil,
            currentdir: URL = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            ),
            sessionStorageMode explicitSessionStorageMode: SessionStorageMode? = nil,
            attachWorkspaceIfProjectDiscovered: Bool = true,
            createHomeDirectories: Bool = true
        ) throws -> AgentRuntimeEnvironment {
            try AgentRuntimeEnvironment.resolve(
                explicitHome: explicitHome,
                explicitHomeRootURL: explicitHomeRootURL,
                explicitWorkspace: explicitWorkspace,
                currentdir: currentdir,
                sessionStorageMode: explicitSessionStorageMode,
                attachWorkspaceIfProjectDiscovered: attachWorkspaceIfProjectDiscovered,
                createHomeDirectories: createHomeDirectories
            )
        }

        public func stores(
            for environment: AgentRuntimeEnvironment,
            sessionID: String
        ) throws -> AgentRuntimeStores {
            try AgentRuntimeStoreResolver(
                environment: environment
            ).resolveStores(
                sessionID: sessionID
            )
        }

        public func session(
            sessionID: String = UUID().uuidString,
            environment: AgentRuntimeEnvironment
        ) throws -> AgentSessionRuntime {
            try AgentSessionRuntime.resolve(
                sessionID: sessionID,
                environment: environment
            )
        }

        public func sessionCatalog(
            environment: AgentRuntimeEnvironment
        ) -> AgentSessionCatalog {
            AgentSessionCatalog(
                environment: environment
            )
        }

        public func taskManager(
            environment: AgentRuntimeEnvironment
        ) throws -> AgentTaskManager {
            try AgentTaskManager.resolve(
                environment: environment
            )
        }
    }

    static let runtime: RuntimeBootstrapAPI = .init()
}

public extension Agentic.RuntimeBootstrapAPI {
    func preparedIntentManager(
        environment: AgentRuntimeEnvironment
    ) throws -> PreparedIntentManager {
        try PreparedIntentManager.resolve(
            environment: environment
        )
    }
}

public extension Agentic.RuntimeBootstrapAPI {
    func pricingCatalog(
        environment: AgentRuntimeEnvironment,
        filename: String = "pricing-catalog.json",
        createDirectories: Bool = true
    ) throws -> FileModelPricingCatalog {
        try environment.filePricingCatalog(
            filename: filename,
            createDirectories: createDirectories
        )
    }

    func costTracker(
        environment: AgentRuntimeEnvironment,
        provider: String,
        region: String? = nil,
        defaultModel: String? = nil,
        reservedOutputTokens: Int = 0,
        catalog: (any ModelPricingCatalog)? = nil,
        metadata: [String: String] = [:]
    ) throws -> AgentCostTracker {
        let catalog = try catalog ?? pricingCatalog(
            environment: environment
        )

        return AgentCostTracker(
            catalog: catalog,
            provider: provider,
            region: region,
            defaultModel: defaultModel,
            reservedOutputTokens: reservedOutputTokens,
            metadata: metadata
        )
    }
}
