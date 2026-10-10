import Agentic
import Foundation

public extension AgentRunner {
    init(
        model: RuntimeServices.Model,
        environment: AgentRuntimeEnvironment,
        sessionID: String,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        capabilityState: AgentCapabilityState,
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
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

        self.init(
            model: model,
            configuration: resolvedConfiguration,
            tooling: tooling.using(
                workspace: try environment.workspace?.context()
            ),
            capabilityState: capabilityState,
            extensions: extensions,
            recording: resolvedRecording
        )
    }
}
