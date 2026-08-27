import Agentic
import AgenticInterfaces

public struct AgenticRuntime:
    Sendable
{
    public let application: AgenticApplication
    public let tools: ToolRegistry
    public let skills: SkillRegistry
    public let adapters: AgentModelAdapterCatalog
    public let profiles: AgentModelProfileCatalog

    public init(
        application: AgenticApplication
    ) async throws {
        let tools = try Agentic.tool.registry {
            application.toolRegistrations
        }

        let skills = try Agentic.skill.registry {
            application.skillRegistrations
        }

        var realizedAdapters: [
            (
                AgentModelAdapterIdentifier,
                any AgentModelAdapter
            )
        ] = []

        realizedAdapters.reserveCapacity(
            application.adapterRegistrations.count
        )

        for registration in application.adapterRegistrations {
            realizedAdapters.append(
                (
                    registration.identifier,
                    try await registration.make()
                )
            )
        }

        self.application = application
        self.tools = tools
        self.skills = skills
        self.adapters = try AgentModelAdapterCatalog(
            adapters: realizedAdapters
        )
        self.profiles = try AgentModelProfileCatalog(
            modelProviders: application.modelProviders
        )
    }
}

public extension AgenticRuntime {
    static func resolve<
        Application: AgenticApplicationProviding
    >(
        _ application: Application.Type
    ) async throws -> Self {
        try await .init(
            application: application.application
        )
    }
}
