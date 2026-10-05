import Agentic
import AgenticModels
import Primitives

public struct AgenticRuntime:
    Sendable
{
    public let application: AgenticApplication
    public let catalog: Catalog
    public let tools: ToolRegistry
    public let toolInventory: ToolInventory
    public let skills: SkillRegistry
    public let programs: ProgramRegistry
    public let agents: AgentRegistry
    public let launches: [ApplicationLaunchEntry]
    public let gateways: GatewayCatalog
    public let profiles: ProfileCatalog

    private let programExecutions:
        [ProgramIdentifier: ProgramRegistration]

    public init(
        application: AgenticApplication
    ) async throws {
        let tools = try Agentic.tool.registry {
            application.toolRegistrations
        }
        let toolInventory = try ToolInventory.materialize(
            registrations: application.toolRegistrations,
            registry: tools
        )

        let skills = try Agentic.skill.registry {
            application.skillRegistrations
        }

        var programs = ProgramRegistry()
        var programExecutions:
            [ProgramIdentifier: ProgramRegistration] = [:]

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

        let agents = try AgentRegistry(
            application.agentDefinitions
        )
        let launches = try validateApplicationLaunchEntries(
            application.launchEntries,
            agents: agents,
            programs: programs
        )

        let modelCatalogs = try await ModelCatalogs(
            modelProviders: application.modelProviders,
            gatewayFactories: application.gatewayFactories
        )

        self.application = application
        self.catalog = application.catalog
        self.tools = tools
        self.toolInventory = toolInventory
        self.skills = skills
        self.programs = programs
        self.agents = agents
        self.launches = launches
        self.gateways = modelCatalogs.gateways
        self.profiles = modelCatalogs.profiles
        self.programExecutions = programExecutions
    }

    public func realizeAgent(
        identifiedBy identifier: AgentIdentifier
    ) throws -> AgentRealization {
        let definition = try agents.requireAgent(
            identifiedBy: identifier
        )

        return AgentRealization.materialize(
            definition: definition,
            catalog: catalog,
            tools: tools,
            programs: programs,
            agents: agents
        )
    }

    public func executeProgram(
        identifiedBy identifier: ProgramIdentifier,
        input: JSONValue,
        realization: JSONValue? = nil,
        services: AgentRuntimeServices = .init(),
        metadata: [String: String] = [:]
    ) async throws -> ProgramExecutionRecord {
        guard let registration = programExecutions[
            identifier
        ] else {
            throw ProgramExecutionError
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

    public func resumeProgram(
        from checkpoint: ProgramCheckpoint,
        interaction response: AgentInteraction.Response,
        services: AgentRuntimeServices = .init()
    ) async throws -> ProgramExecutionRecord {
        let identifier = checkpoint.programIdentifier

        guard let registration = programExecutions[
            identifier
        ] else {
            throw ProgramExecutionError
                .registrationUnavailable(
                    identifier
                )
        }

        return try await registration.resume(
            from: checkpoint,
            interaction: response,
            services: services
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
