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
        tooling: AgentRuntimeServices.Tooling = .init(),
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

        self.init(
            model: model,
            configuration: resolvedConfiguration,
            tooling: tooling.using(
                workspace: environment.workspace
            ),
            extensions: extensions,
            recording: resolvedRecording
        )
    }
}
