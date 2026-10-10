import Agentic

public enum RuntimeDiagnosticWarning:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case catalog_inferences_not_executable
    case programs_not_model_callable
    case agents_not_model_callable
}

public struct AgentRuntimeDiagnostics:
    Sendable,
    Codable,
    Hashable
{
    public let identifier: AgentIdentifier
    public let requestedAvailable: AgentCapabilitySet
    public let requestedVisible: AgentCapabilitySet
    public let installed: AgentCapabilitySet
    public let available: AgentCapabilitySet
    public let visible: AgentCapabilitySet

    public init(
        identifier: AgentIdentifier,
        requestedAvailable: AgentCapabilitySet,
        requestedVisible: AgentCapabilitySet,
        installed: AgentCapabilitySet,
        available: AgentCapabilitySet,
        visible: AgentCapabilitySet
    ) {
        self.identifier = identifier
        self.requestedAvailable = requestedAvailable
        self.requestedVisible = requestedVisible
        self.installed = installed
        self.available = available
        self.visible = visible
    }
}

public struct RuntimeDiagnostics:
    Sendable,
    Codable,
    Hashable
{
    public let application: AgenticApplicationIdentifier
    public let catalog: AgentCapabilitySet
    public let installed: AgentCapabilitySet
    public let modelCallable: AgentCapabilitySet

    public let registeredTools: Int
    public let modelFacingTools: Int
    public let skills: [AgentSkillIdentifier]
    public let launches: [ApplicationLaunchIdentifier]

    public let availableGateways: [AgentModelGatewayIdentifier]
    public let unavailableGateways: [AgentModelGatewayIdentifier]
    public let profiles: [AgentModelProfileIdentifier]

    public let agents: [AgentRuntimeDiagnostics]
    public let warnings: [RuntimeDiagnosticWarning]

    public init(
        application: AgenticApplicationIdentifier,
        catalog: AgentCapabilitySet,
        installed: AgentCapabilitySet,
        modelCallable: AgentCapabilitySet,
        registeredTools: Int,
        modelFacingTools: Int,
        skills: [AgentSkillIdentifier],
        launches: [ApplicationLaunchIdentifier],
        availableGateways: [AgentModelGatewayIdentifier],
        unavailableGateways: [AgentModelGatewayIdentifier],
        profiles: [AgentModelProfileIdentifier],
        agents: [AgentRuntimeDiagnostics],
        warnings: [RuntimeDiagnosticWarning]
    ) {
        self.application = application
        self.catalog = catalog
        self.installed = installed
        self.modelCallable = modelCallable
        self.registeredTools = registeredTools
        self.modelFacingTools = modelFacingTools
        self.skills = skills
        self.launches = launches
        self.availableGateways = availableGateways
        self.unavailableGateways = unavailableGateways
        self.profiles = profiles
        self.agents = agents
        self.warnings = warnings
    }
}

public extension AgenticRuntime {
    func diagnostics() throws -> RuntimeDiagnostics {
        let catalogCapabilities = AgentCapabilitySet(
            tools: catalog.tools.map(
                \.identifier
            ),
            programs: catalog.programs.map(
                \.identifier
            ),
            inferences: catalog.inferences.map(
                \.identifier
            ),
            agents: catalog.agents.map(
                \.identifier
            )
        )

        let installedCapabilities = installed.capabilities

        // Provider function/tool projection currently supports Tool definitions.
        // Programs, Inferences, and Agents become non-empty here when their
        // generalized model-call projection is implemented.
        let modelCallableCapabilities = AgentCapabilitySet(
            tools: tools.modelFacingDefinitions.map(
                \.identifier
            )
        )

        let agentDiagnostics = try agents.definitions.map { definition in
            try diagnostics(
                for: definition.identifier
            )
        }

        var warnings: [RuntimeDiagnosticWarning] = []

        if !Set(catalogCapabilities.inferences)
            .subtracting(installedCapabilities.inferences)
            .isEmpty
        {
            warnings.append(
                .catalog_inferences_not_executable
            )
        }

        if !installedCapabilities.programs.isEmpty,
           modelCallableCapabilities.programs.isEmpty
        {
            warnings.append(
                .programs_not_model_callable
            )
        }

        if !installedCapabilities.agents.isEmpty,
           modelCallableCapabilities.agents.isEmpty
        {
            warnings.append(
                .agents_not_model_callable
            )
        }

        return RuntimeDiagnostics(
            application: application.identifier,
            catalog: catalogCapabilities,
            installed: installedCapabilities,
            modelCallable: modelCallableCapabilities,
            registeredTools: installed.tools.count,
            modelFacingTools: installed.tools.modelFacingDefinitions.count,
            skills: skills.skills_sorted.map(
                \.identifier
            ),
            launches: launches.map(
                \.identifier
            ),
            availableGateways: gateways.gatewaysByIdentifier.keys.sorted {
                $0.rawValue < $1.rawValue
            },
            unavailableGateways: gateways.unavailabilityByIdentifier.keys.sorted {
                $0.rawValue < $1.rawValue
            },
            profiles: profiles.profilesByIdentifier.keys.sorted {
                $0.rawValue < $1.rawValue
            },
            agents: agentDiagnostics,
            warnings: warnings
        )
    }

    func diagnostics(
        for agent: AgentIdentifier
    ) throws -> AgentRuntimeDiagnostics {
        let realization = try realizeAgent(
            identifiedBy: agent
        )

        return AgentRuntimeDiagnostics(
            identifier: realization.identifier,
            requestedAvailable: realization.requestedAvailable,
            requestedVisible: realization.requestedVisible,
            installed: realization.installed,
            available: realization.available,
            visible: realization.visible
        )
    }
}
