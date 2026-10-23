// FROZEN: deferred queue (not conversational or ToolPlan execution).
#if AGENTIC_ENABLE_DEFERRED_INTENTS
import Agentic

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

#endif // AGENTIC_ENABLE_DEFERRED_INTENTS