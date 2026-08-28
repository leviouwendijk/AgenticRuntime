import Agentic
import AgenticExecution
import Foundation

public extension ToolLoopExecutor {
    init(
        adapter: any AgentModelAdapter,
        environment: AgentRuntimeEnvironment,
        sessionID: String,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        enableHistoryPersistence: Bool = true
    ) throws {
        let stores = try AgentRuntimeStoreResolver(
            environment: environment
        ).resolveStores(
            sessionID: sessionID
        )

        var resolvedConfiguration = configuration

        if enableHistoryPersistence,
           stores.historyStore != nil,
           resolvedConfiguration.historyPersistenceMode == .disabled {
            resolvedConfiguration.historyPersistenceMode = .checkpointmutation
        }

        self.init(
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
}
