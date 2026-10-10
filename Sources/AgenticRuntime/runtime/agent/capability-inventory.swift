import Agentic
import Primitives

/// An Agent-scoped, copy-on-write view of the application's installed bindings.
/// Installing, enabling, and exposing are separate operations.
public actor CapabilityInventory {
    public typealias Subset = AgentCapabilitySet
    public let state: AgentCapabilityState
    private var entries: InstalledCapabilities
    private var revisionNumber: UInt64 = 0

    public init(installed: InstalledCapabilities, state: AgentCapabilityState) {
        self.entries = installed
        self.state = state
    }

    public init(
        tools: ToolRegistry = .init(),
        catalog: Catalog = .none,
        programs: [ProgramExecutionBinding] = [],
        inferences: [InferenceBinding] = [],
        agents: [AgentBinding] = [],
        state: AgentCapabilityState
    ) {
        self.entries = InstalledCapabilities(
            tools: tools, catalog: catalog, programs: programs,
            inferences: inferences, agents: agents
        )
        self.state = state
    }

    public var revision: UInt64 { revisionNumber }
    public func tools() -> ToolRegistry { entries.tools }
    public func catalog() -> Catalog { entries.catalog }
    public func capabilityInspections() -> [CapabilityInspection] {
        entries.capabilityInspections()
    }

    /// Canonical model function projection over this Agent's executable view.
    /// The visible snapshot is captured with the inventory read; no second
    /// registry of model functions is maintained.
    public func modelProjection() async throws -> ModelCapabilityProjection {
        try entries.modelProjection(visible: await state.snapshot().visible)
    }

    /// Native Tool transport remains Tool-specific, but definitions are
    /// derived from the same installed bindings and visible selection.
    public func modelFacingToolDefinitions() async throws -> [ToolDescriptor] {
        let visible = await state.snapshot().visible
        return try entries.tools.modelFacingDefinitions(for: visible.tools)
    }
    public func adapters() -> InferenceAdapterCatalog { entries.adapters }
    public func program(_ id: ProgramIdentifier) -> ProgramExecutionBinding? {
        entries.program(id)
    }
    public func inference(_ id: InferenceIdentifier) -> InferenceBinding? {
        entries.inference(id)
    }
    public func agent(_ id: AgentIdentifier) -> AgentDefinition? {
        entries.agentBinding(id)?.definition
    }
    public func agentBinding(_ id: AgentIdentifier) -> AgentBinding? {
        entries.agentBinding(id)
    }

    /// Adapter installation never grants or exposes an Agent-callable capability.
    public func install(_ adapter: any InferenceAdapter) throws {
        var updated = entries
        try updated.install(adapter)
        entries = updated
        revisionNumber &+= 1
    }

    public func install<A: InferenceAdapterFor>(_ adapter: A) throws {
        try install(TypedInferenceAdapter(adapter))
    }

    @discardableResult
    public func install<T: Tool>(
        _ tool: T,
        modelContract: ToolModelContract? = nil
    ) async throws -> AgentCapabilityState.Snapshot {
        var updated = entries
        try updated.install(tool, modelContract: modelContract)
        entries = updated
        revisionNumber &+= 1
        return await state.install(.init(tools: [T.definition.identifier]))
    }

    @discardableResult
    public func install(
        _ binding: ProgramExecutionBinding
    ) async throws -> AgentCapabilityState.Snapshot {
        var updated = entries
        try updated.install(binding)
        entries = updated
        revisionNumber &+= 1
        return await state.install(.init(programs: [binding.identifier]))
    }

    @discardableResult
    public func install(
        _ binding: InferenceBinding
    ) async throws -> AgentCapabilityState.Snapshot {
        var updated = entries
        try updated.install(binding)
        entries = updated
        revisionNumber &+= 1
        return await state.install(.init(inferences: [binding.identifier]))
    }

    @discardableResult
    public func install(
        _ binding: AgentBinding
    ) async throws -> AgentCapabilityState.Snapshot {
        var updated = entries
        try updated.install(binding)
        entries = updated
        revisionNumber &+= 1
        return await state.install(.init(agents: [binding.definition.identifier]))
    }

    /// Apply the entire capability batch or none of it.
    @discardableResult
    public func install(
        _ installation: Installation
    ) async throws -> AgentCapabilityState.Snapshot {
        var updated = entries
        try updated.install(installation)
        let newlyInstalled = updated.capabilities.subtracting(entries.capabilities)
        entries = updated
        revisionNumber &+= 1
        return await state.install(newlyInstalled)
    }

    @discardableResult
    public func install<P: Program>(
        _ program: P,
        realization: ProgramRealization<P>? = nil
    ) async throws -> AgentCapabilityState.Snapshot {
        try await install(ProgramExecutionBinding(program, defaultRealization: realization))
    }

    @discardableResult
    public func install<I: Inference>(
        _ inference: I.Type,
        realization: InferenceRealizationConfiguration? = nil
    ) async throws -> AgentCapabilityState.Snapshot {
        try await install(InferenceBinding(inference, defaultRealization: realization))
    }

    @discardableResult
    public func install<A: Agent>(
        _ agent: A.Type
    ) async throws -> AgentCapabilityState.Snapshot {
        try await install(AgentBinding(agent))
    }

    @discardableResult
    public func enable(
        _ selection: AgentCapabilitySet
    ) async throws -> AgentCapabilityState.Snapshot {
        let missing = selection.subtracting(entries.capabilities)
        guard missing == .none else {
            throw AgentCapabilityMutationError.notInstalled(missing)
        }
        let snapshot = try await state.enable(selection)
        revisionNumber &+= 1
        return snapshot
    }

    @discardableResult
    public func expose(
        _ selection: AgentCapabilitySet
    ) async throws -> AgentCapabilityState.Snapshot {
        let snapshot = try await state.expose(selection)
        revisionNumber &+= 1
        return snapshot
    }

    @discardableResult
    public func disable(
        _ selection: AgentCapabilitySet
    ) async -> AgentCapabilityState.Snapshot {
        let snapshot = await state.disable(selection)
        revisionNumber &+= 1
        return snapshot
    }

    @discardableResult
    public func hide(
        _ selection: AgentCapabilitySet
    ) async -> AgentCapabilityState.Snapshot {
        let snapshot = await state.unexpose(selection)
        revisionNumber &+= 1
        return snapshot
    }

    public func snapshot() async -> AgentCapabilityState.Snapshot {
        await state.snapshot()
    }
}

public enum CapabilityInventoryError: Error, Sendable {
    case duplicateProgram(ProgramIdentifier)
    case duplicateInference(InferenceIdentifier)
    case duplicateAgent(AgentIdentifier)
    case notCapabilityInstallation
}

private func capabilitiesOf<D: Domain>(_ domain: D.Type) -> Installation {
    install(domain)
}

public extension CapabilityInventory {
    @discardableResult
    func install<D: Domain>(
        _ domain: D.Type
    ) async throws -> AgentCapabilityState.Snapshot {
        try await install(capabilitiesOf(domain))
    }
}

