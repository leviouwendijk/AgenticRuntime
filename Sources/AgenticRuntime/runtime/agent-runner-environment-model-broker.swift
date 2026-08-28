import Agentic
import AgenticExecution
import AgenticModels
import AgenticUsage

public extension AgentRunner {
    init(
        modelBroker: AgentModelBroker,
        environment: AgentRuntimeEnvironment,
        sessionID: String,
        routePolicy: AgentModelUsePolicy = .executor,
        configuration: AgentRunnerConfiguration = .default,
        toolRegistry: ToolRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        approvalHandler: (any ToolApprovalHandler)? = nil,
        costTracker: AgentCostTracker? = nil,
        enableHistoryPersistence: Bool = true
    ) throws {
        try self.init(
            adapter: AgentModelBrokerAdapter(
                broker: modelBroker,
                policy: routePolicy
            ),
            environment: environment,
            sessionID: sessionID,
            configuration: configuration,
            toolRegistry: toolRegistry,
            extensions: extensions,
            approvalHandler: approvalHandler,
            costTracker: costTracker,
            enableHistoryPersistence: enableHistoryPersistence
        )
    }
}
