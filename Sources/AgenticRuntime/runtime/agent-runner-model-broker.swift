import Agentic
import AgenticExecution
import AgenticModels
import AgenticUsage
import AgenticWorkspace

public extension AgentRunner {
    init(
        modelBroker: AgentModelBroker,
        routePolicy: AgentModelUsePolicy = .executor,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        workspace: AgentWorkspace? = nil,
        approvalHandler: (any ToolApprovalHandler)? = nil,
        historyStore: (any AgentHistoryStore)? = nil,
        eventSinks: [any AgentRunEventSink] = [],
        costTracker: AgentCostTracker? = nil
    ) {
        self.init(
            adapter: AgentModelBrokerAdapter(
                broker: modelBroker,
                policy: routePolicy
            ),
            configuration: configuration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            workspace: workspace,
            approvalHandler: approvalHandler,
            historyStore: historyStore,
            eventSinks: eventSinks,
            costTracker: costTracker
        )
    }
}
