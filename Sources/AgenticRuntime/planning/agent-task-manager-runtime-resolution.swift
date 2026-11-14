import Agentic

public extension AgentTaskManager {
    static func resolve(
        environment: AgentRuntimeEnvironment
    ) throws -> Self {
        guard let tasksdir = environment.tasksdir() else {
            throw AgentTaskError.durableStorageRequired
        }

        return .init(
            store: FileAgentTaskStore(
                tasksdir: tasksdir
            )
        )
    }

    /// The task graph stored beside a home's sessions and logs.
    static func home(
        _ home: AgentHome
    ) -> Self {
        .init(
            store: FileAgentTaskStore(
                tasksdir: home.layout.runtimeStorage.tasksdir
            )
        )
    }
}
