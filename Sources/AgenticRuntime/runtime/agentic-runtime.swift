import Agentic
import AgenticExecution
import AgenticModels

public struct AgenticRuntime:
    Sendable
{
    public let application: AgenticApplication
    public let tools: ToolRegistry
    public let toolCatalog: AgentToolCatalog
    public let skills: SkillRegistry
    public let gateways: AgentModelGatewayCatalog
    public let profiles: AgentModelProfileCatalog

    public init(
        application: AgenticApplication
    ) async throws {
        let tools = try Agentic.tool.registry {
            application.toolRegistrations
        }
        let toolCatalog = try AgenticRuntimeToolCatalog.materialize(
            registrations: application.toolRegistrations,
            registry: tools
        )

        let skills = try Agentic.skill.registry {
            application.skillRegistrations
        }

        var gatewayOverrides: [any AgentModelGateway] = []

        gatewayOverrides.reserveCapacity(
            application.gatewayFactories.count
        )

        for factory in application.gatewayFactories {
            gatewayOverrides.append(
                try await factory.make()
            )
        }

        let modelCatalogs = try await AgentModelCatalogs(
            modelProviders: application.modelProviders,
            gatewayOverrides: gatewayOverrides
        )

        self.application = application
        self.tools = tools
        self.toolCatalog = toolCatalog
        self.skills = skills
        self.gateways = modelCatalogs.gateways
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
