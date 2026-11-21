import Agentic
import AgenticConfiguration
import AgenticIntents
import Foundation

public extension AgentRuntimeEnvironment {
    /// The intents stored beside this environment's sessions; nil when it
    /// keeps nothing durable.
    func intentManager() -> Intents.Manager? {
        intentsdir().map {
            Intents.Manager(
                store: Intents.FileStore(directory: $0)
            )
        }
    }
}

public extension Intents.Manager {
    /// The intents stored beside a home's sessions and logs.
    static func home(
        _ home: AgentHome
    ) -> Intents.Manager {
        .init(
            store: Intents.FileStore(
                directory: home.layout.runtimeStorage.intentsdir
            )
        )
    }
}
