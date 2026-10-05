import Agentic
import Foundation

public extension ToolLoopExecutor {
    init(
        model: AgentRuntimeServices.Model,
        environment: AgentRuntimeEnvironment,
        sessionID: String,
        configuration: AgentRunnerConfiguration = .default,
        tooling: AgentRuntimeServices.Tooling = .init(),
        capabilityState: AgentCapabilityState? = nil,
        extensions: [any AgentHarnessExtension] = [],
        recording: AgentRuntimeServices.Recording = .init(),
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

        let resolvedRecording = recording.resolving(
            historyStore: stores.historyStore,
            eventSinks: stores.eventSinks
        )

        let resolvedTooling = tooling.using(
            workspace: try environment.workspace?.context()
        )
        let resolvedCapabilities =
            capabilityState
            ?? AgentCapabilityState(
                installed: .init(
                    tools: resolvedTooling.registry
                        .modelFacingDefinitions
                        .map(\.identifier)
                )
            )

        self.init(
            model: model,
            configuration: resolvedConfiguration,
            tooling: resolvedTooling,
            capabilityState: resolvedCapabilities,
            extensions: extensions,
            recording: resolvedRecording
        )
    }
}
