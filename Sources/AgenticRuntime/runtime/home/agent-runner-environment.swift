import Agentic
import AgenticExecution
import AgenticUsage
import Foundation

public extension AgentRunner {
    init(
        model: AgentRuntimeServices.Model,
        environment: AgentRuntimeEnvironment,
        sessionID: String,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        stateSinks: [any AgentRunStateSink] = [],
        costTracker: AgentCostTracker? = nil,
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
            model: model,
            configuration: resolvedConfiguration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            workspace: environment.workspace,
            approvalHandler: approvalHandler,
            historyStore: stores.historyStore,
            eventSinks: stores.eventSinks,
            stateSinks: stateSinks,
            costTracker: costTracker
        )
    }
}
