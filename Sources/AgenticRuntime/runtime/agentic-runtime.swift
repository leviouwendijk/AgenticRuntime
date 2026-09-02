import Agentic
import AgenticExecution
import AgenticInterfaces
import AgenticModels

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

        var adapterOverrides: [
            (
                AgentModelAdapterIdentifier,
                any AgentModelAdapter
            )
        ] = []

        adapterOverrides.reserveCapacity(
            application.adapterRegistrations.count
        )

        for registration in application.adapterRegistrations {
            adapterOverrides.append(
                (
                    registration.identifier,
                    try await registration.make()
                )
            )
        }

        let modelCatalogs = try await AgentModelCatalogs(
            modelProviders: application.modelProviders,
            adapterOverrides: adapterOverrides
        )

        self.application = application
        self.tools = tools
        self.skills = skills
        self.adapters = modelCatalogs.adapters
        self.profiles = modelCatalogs.profiles
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
