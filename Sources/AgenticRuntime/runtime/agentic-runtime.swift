import Agentic
import AgenticModels
import Primitives

public struct AgenticRuntime:
    Sendable
{
    public let application: AgenticApplication
    public let installed: InstalledCapabilities
    public var catalog: Catalog { installed.catalog }
    public var adapters: InferenceAdapterCatalog { installed.adapters }

    /// Construct an executor using precisely this application's installed adapters.
    /// Model routing remains independent of adapter installation.
    public func makeInferenceExecutor(
        modelInvoker: any AgentModelInvoking,
        defaultAdapterIdentifier: InferenceAdapterIdentifier? = nil
    ) -> InferenceExecutor {
        InferenceExecutor(
            modelInvoker: modelInvoker,
            adapters: installed.adapters,
            defaultAdapterIdentifier: defaultAdapterIdentifier
        )
    }
    public var tools: ToolRegistry { installed.tools }
    public let skills: SkillRegistry
    public var programs: InstalledCapabilities.Programs { installed.programs }
    public var inferences: InstalledCapabilities.Inferences { installed.inferences }
    public var agents: InstalledCapabilities.Agents { installed.agents }

    /// Presentation metadata derived on demand from the installed Tool bindings
    /// and authored collection grouping. It is not an execution registry or
    /// a mutable source of capability authority.
    public func toolPresentation() throws -> ToolInventory {
        try ToolInventory.materialize(
            registrations: application.toolRegistrations,
            registry: installed.tools
        )
    }

    public let launches: [ApplicationLaunchEntry]
    public let gateways: GatewayCatalog
    public let profiles: ProfileCatalog

    public init(
        application: AgenticApplication
    ) async throws {
        let installed = try InstalledCapabilities(application: application)
        let skills = try Agentic.skill.registry {
            application.skillRegistrations
        }
        let launches = try validateApplicationLaunchEntries(
            application.launchEntries,
            installed: installed
        )

        let modelCatalogs = try await ModelCatalogs(
            modelProviders: application.modelProviders,
            gatewayFactories: application.gatewayFactories
        )

        self.application = application
        self.installed = installed
        self.skills = skills
        self.launches = launches
        self.gateways = modelCatalogs.gateways
        self.profiles = modelCatalogs.profiles
    }

    public func realizeAgent(
        identifiedBy identifier: AgentIdentifier
    ) throws -> AgentRealization {
        let definition = try agents.requireAgent(
            identifiedBy: identifier
        )

        return AgentRealization.materialize(
            definition: definition,
            installed: installed
        )
    }

    /// Execute an installed Inference through Agentic's canonical executor.
    public func executeInference(
        identifiedBy identifier: InferenceIdentifier,
        input: JSONValue,
        realization: InferenceRealizationConfiguration? = nil,
        using executor: any InferenceExecuting,
        context: InferenceExecutionContext = .default
    ) async throws -> InferenceInvocation.Response {
        guard let registration = installed.inference(identifier) else {
            throw InferenceRegistryError.unknownInference(identifier)
        }
        return try await registration.execute(
            input: input,
            realization: realization,
            using: executor,
            context: context
        )
    }

    /// Compatibility entry point for state-only callers. Projection logic
    /// lives in the installed bindings, not in this façade.
    public func modelProjection(
        for capabilityState: AgentCapabilityState
    ) async throws -> ModelCapabilityProjection {
        try installed.modelProjection(
            visible: await capabilityState.snapshot().visible
        )
    }

    /// Agent-local installation and exposure are read together from the
    /// inventory, so newly installed or revoked bindings are not lost.
    public func modelProjection(
        for inventory: CapabilityInventory
    ) async throws -> ModelCapabilityProjection {
        try await inventory.modelProjection()
    }

    public func executeProgram(
        identifiedBy identifier: ProgramIdentifier,
        input: JSONValue,
        realization: JSONValue? = nil,
        services: RuntimeServices = .init(),
        metadata: [String: String] = [:]
    ) async throws -> ProgramExecutionRecord {
        guard let registration = installed.program(identifier) else {
            throw ProgramExecutionError
                .bindingUnavailable(
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
        interaction response: Run.Interaction.Response,
        services: RuntimeServices = .init()
    ) async throws -> ProgramExecutionRecord {
        let identifier = checkpoint.programIdentifier

        guard let registration = installed.program(identifier) else {
            throw ProgramExecutionError
                .bindingUnavailable(
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
