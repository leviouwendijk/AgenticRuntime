import Agentic
import AgenticModels
import Primitives

public struct AgenticRuntime:
    Sendable
{
    public let application: AgenticApplication
    public let installed: InstalledCapabilities
    public var catalog: Catalog { installed.catalog }
    /// Authored, metadata-only instructions; not executable capabilities.
    public var instructions: [InstructionDefinition] { installed.instructions }

    public func selectInstructions(
        _ identifiers: [InstructionIdentifier]
    ) throws -> InstructionSelection {
        try catalog.selectingInstructions(identifiers)
    }

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
    public var programs: InstalledCapabilities.Programs { installed.programs }
    public var inferences: InstalledCapabilities.Inferences { installed.inferences }
    public var agents: InstalledCapabilities.Agents { installed.agents }

    /// Presentation metadata derived on demand from the installed Tool bindings
    /// and authored collection grouping. It is not an execution registry or
    /// a mutable source of capability authority.
    public func toolPresentation() throws -> ToolInventory {
        try ToolInventory.materialize(
            bindings: application.toolBindings,
            registry: installed.tools
        )
    }

    public let launches: [ApplicationLaunchEntry]
    public let gateways: GatewayCatalog
    public let profiles: ProfileCatalog
    public let pricing: StaticModelPricingCatalog

    /// `livePricing` layers provider-published prices over the curated
    /// ones; without it, pricing stays offline.
    public init(
        application: AgenticApplication,
        livePricing: LivePricingCache? = nil
    ) async throws {
        let installed = try InstalledCapabilities(application: application)
        let launches = try validateApplicationLaunchEntries(
            application.launchEntries,
            installed: installed
        )

        let modelCatalogs = try await ModelCatalogs(
            modelProviders: application.modelProviders,
            gatewayFactories: application.gatewayFactories
        )

        let preferred = application.modelSelection.preferences
        let routable = modelCatalogs.profiles.routable(using: modelCatalogs.gateways)
        if let profile = preferred.preferredProfileIdentifier,
           routable.profilesByIdentifier[profile] == nil
        {
            throw ApplicationModelSelectionError.unavailable_profile(profile)
        }
        if let model = preferred.preferredModelID,
           !routable.profiles(for: model).contains(where: {
               preferred.gateway == nil || $0.gatewayIdentifier == preferred.gateway
           })
        {
            throw ApplicationModelSelectionError.unavailable_model(model, preferred.gateway)
        }
        if let gateway = preferred.gateway,
           !routable.profilesByIdentifier.values.contains(where: {
               $0.gatewayIdentifier == gateway
           })
        {
            throw ApplicationModelSelectionError.unavailable_gateway(gateway)
        }

        self.application = application
        self.installed = installed
        self.launches = launches
        self.gateways = modelCatalogs.gateways
        self.profiles = modelCatalogs.profiles
        var pricing = modelCatalogs.pricing
        if let livePricing {
            for snapshot in await livePricing.snapshots(for: application.modelProviders) {
                pricing.insert(snapshot)
            }
        }
        self.pricing = pricing
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
        sessionID: String? = nil,
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
            sessionID: sessionID,
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
            application: application.application,
            livePricing: .home(AgentHomeLocator().resolveHome())
        )
    }
}
