import AgenticExecution

public extension PreparedIntentManager {
    static func resolve(
        environment: AgentRuntimeEnvironment
    ) throws -> Self {
        guard let preparedIntentsdir = environment.preparedintentsdir() else {
            throw PreparedIntentError.durableStorageRequired
        }

        return .init(
            store: FilePreparedIntentStore(
                preparedIntentsdir: preparedIntentsdir
            )
        )
    }
}
