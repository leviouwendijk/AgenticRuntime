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
}
