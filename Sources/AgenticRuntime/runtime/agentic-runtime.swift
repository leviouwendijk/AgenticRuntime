import Agentic
import AgenticExecution
import AgenticModels
import AgenticPrograms
import Primitives

public struct AgenticRuntime:
    Sendable
{
    public let application: AgenticApplication
    public let tools: ToolRegistry
    public let toolCatalog: AgentToolCatalog
    public let skills: SkillRegistry
    public let programs: ProgramRegistry
    public let gateways: AgentModelGatewayCatalog
    public let profiles: AgentModelProfileCatalog

    private let programExecutions:
        [AgentProgramIdentifier: AgentRuntimeProgramRegistration]

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

        var programs = ProgramRegistry()
        var programExecutions:
            [AgentProgramIdentifier: AgentRuntimeProgramRegistration] = [:]

        programExecutions.reserveCapacity(
            application.programRegistrations.count
        )

        for registration in application.programRegistrations {
            try programs.register(
                registration.registeredProgram
            )
            programExecutions[
                registration.identifier
            ] = registration
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
        self.programs = programs
        self.gateways = modelCatalogs.gateways
        self.profiles = modelCatalogs.profiles
        self.programExecutions = programExecutions
    }

    public func executeProgram(
        identifiedBy identifier: AgentProgramIdentifier,
        input: JSONValue,
        realization: JSONValue? = nil,
        services: AgentRuntimeServices = .init(),
        metadata: [String: String] = [:]
    ) async throws -> AgentProgramExecutionRecord {
        guard let registration = programExecutions[
            identifier
        ] else {
            throw AgentRuntimeProgramExecutionError
                .registrationUnavailable(
                    identifier
                )
        }

        return try await registration.execute(
            input: input,
            realization: realization,
            services: services,
            metadata: metadata
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
