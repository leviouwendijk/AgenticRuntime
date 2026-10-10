import Agentic
import Primitives

/// Materialized executable installation. Catalog declarations alone are not installed.
/// Value semantics let an Agent extend its own copy without changing the application.
public struct InstalledCapabilities: Sendable {
    public private(set) var tools: ToolRegistry
    public private(set) var catalog: Catalog
    /// Metadata-only declarations; not installed executable capabilities.
    public var instructions: [InstructionDefinition] { catalog.instructions }
    public private(set) var adapters: InferenceAdapterCatalog
    private var programEntries: [ProgramIdentifier: ProgramExecutionBinding]
    private var inferenceEntries: [InferenceIdentifier: InferenceBinding]
    private var agentEntries: [AgentIdentifier: AgentBinding]

    public init(
        tools: ToolRegistry = .init(),
        catalog: Catalog = .none,
        adapters: InferenceAdapterCatalog = .init(),
        programs: [ProgramExecutionBinding] = [],
        inferences: [InferenceBinding] = [],
        agents: [AgentBinding] = []
    ) {
        self.tools = tools
        self.catalog = catalog
        self.adapters = adapters
        self.programEntries = Dictionary(uniqueKeysWithValues:
            programs.map { ($0.identifier, $0) })
        self.inferenceEntries = Dictionary(uniqueKeysWithValues:
            inferences.map { ($0.identifier, $0) })
        self.agentEntries = Dictionary(uniqueKeysWithValues:
            agents.map { ($0.definition.identifier, $0) })
    }

    public init(application: AgenticApplication) throws {
        self.init()
        catalog = application.catalog
        for registration in application.toolRegistrations {
            try registration.apply(into: &tools)
        }
        for binding in application.programBindings {
            try install(binding)
        }
        for binding in application.inferenceBindings {
            try install(binding)
        }
        for adapter in application.adapterRegistrations {
            try install(adapter)
        }
        for binding in application.agentBindings {
            try install(binding)
        }
    }

    /// Recomputed from actual installed bindings; never a second registry.
    public func capabilityInspections() -> [CapabilityInspection] {
        var namespaces: [CapabilityReference: String] = [:]
        for entry in catalog.entries {
            guard let namespace = entry.namespace?.rawValue else { continue }
            let reference: CapabilityReference
            switch entry.declaration {
            case .tool(let definition): reference = .tool(definition.identifier)
            case .program(let definition): reference = .program(definition.identifier)
            case .inference(let definition): reference = .inference(definition.identifier)
            case .agent(let definition): reference = .agent(definition.identifier)
            case .adapter, .instruction: continue
            }
            namespaces[reference] = namespace
        }

        var result: [CapabilityInspection] = []
        for definition in tools.definitions {
            guard let binding = tools.registeredTool(identifiedBy: definition.identifier) else {
                continue
            }
            let reference = binding.reference
            result.append(.init(
                reference: reference,
                namespace: namespaces[reference],
                purpose: binding.definition.purpose,
                input: binding.capabilityContract.input.jsonvalue,
                output: binding.capabilityContract.output.jsonvalue,
                modelInputSchema: binding.modelFacingInputSchema?.jsonvalue,
                risk: binding.definition.risk
            ))
        }
        for definition in programs.definitions {
            guard let binding = program(definition.identifier) else { continue }
            let reference = binding.reference
            result.append(.init(
                reference: reference, namespace: namespaces[reference],
                purpose: definition.purpose,
                input: binding.capabilityContract.input.jsonvalue,
                output: binding.capabilityContract.output.jsonvalue,
                modelInputSchema: binding.modelFacingInputSchema.jsonvalue
            ))
        }
        for definition in inferences.definitions {
            guard let binding = inference(definition.identifier) else { continue }
            let reference = binding.reference
            result.append(.init(
                reference: reference, namespace: namespaces[reference],
                purpose: definition.purpose,
                input: binding.capabilityContract.input.jsonvalue,
                output: binding.capabilityContract.output.jsonvalue,
                modelInputSchema: binding.modelFacingInputSchema.jsonvalue
            ))
        }
        for definition in agents.definitions {
            guard let binding = agentBinding(definition.identifier) else { continue }
            let reference = binding.reference
            result.append(.init(
                reference: reference, namespace: namespaces[reference],
                purpose: definition.purpose,
                input: binding.capabilityContract.input.jsonvalue,
                output: binding.capabilityContract.output.jsonvalue
            ))
        }
        return result.sorted {
            $0.kind == $1.kind ? $0.identifier < $1.identifier : $0.kind < $1.kind
        }
    }

    public var capabilities: AgentCapabilitySet {
        AgentCapabilitySet(
            tools: tools.definitions.map(\.identifier),
            programs: Array(programEntries.keys),
            inferences: Array(inferenceEntries.keys),
            agents: Array(agentEntries.keys)
        )
    }

    public func program(_ id: ProgramIdentifier) -> ProgramExecutionBinding? {
        programEntries[id]
    }

    public func inference(_ id: InferenceIdentifier) -> InferenceBinding? {
        inferenceEntries[id]
    }

    public func agentBinding(_ id: AgentIdentifier) -> AgentBinding? {
        agentEntries[id]
    }

    /// Read-only compatibility views; they do not own installed implementations.
    public var programs: Programs { .init(entries: programEntries) }
    public var inferences: Inferences { .init(entries: inferenceEntries) }
    public var agents: Agents { .init(entries: agentEntries) }

    public struct Programs: Sendable {
        fileprivate let entries: [ProgramIdentifier: ProgramExecutionBinding]
        public var count: Int { entries.count }
        public var isEmpty: Bool { entries.isEmpty }
        public var definitions: [ProgramDefinition] {
            entries.values.map(\.definition).sorted { lhs, rhs in
                let left = lhs.title ?? lhs.identifier.rawValue
                let right = rhs.title ?? rhs.identifier.rawValue
                return left == right
                    ? lhs.identifier.rawValue < rhs.identifier.rawValue
                    : left < right
            }
        }
        public func registeredProgram(identifiedBy id: ProgramIdentifier) -> ProgramBinding? {
            entries[id]?.program
        }
        public func registeredProgram(named name: String) -> ProgramBinding? {
            registeredProgram(identifiedBy: .init(rawValue: name))
        }
        public func requireProgram(identifiedBy id: ProgramIdentifier) throws -> ProgramBinding {
            guard let binding = registeredProgram(identifiedBy: id) else {
                throw ProgramRegistryError.unknownProgram(id.rawValue)
            }
            return binding
        }
        public func run(
            identifiedBy id: ProgramIdentifier,
            input: JSONValue,
            in context: ProgramContext
        ) async throws -> JSONValue {
            try await requireProgram(identifiedBy: id).run(input: input, in: context)
        }
        public func run<P: Program>(
            _ program: P.Type,
            input: P.Input,
            in context: ProgramContext
        ) async throws -> P.Output {
            let encoded = try JSONValue.encoding(input)
            let output = try await run(
                identifiedBy: P.definition.identifier,
                input: encoded,
                in: context
            )
            return try output.decode(P.Output.self)
        }
    }

    public struct Inferences: Sendable {
        fileprivate let entries: [InferenceIdentifier: InferenceBinding]
        public var definitions: [InferenceDefinition] {
            entries.values.map(\.definition)
                .sorted { $0.identifier.rawValue < $1.identifier.rawValue }
        }
        public func binding(identifiedBy id: InferenceIdentifier) -> InferenceBinding? {
            entries[id]
        }
        public func requireBinding(identifiedBy id: InferenceIdentifier) throws -> InferenceBinding {
            guard let binding = entries[id] else {
                throw InferenceRegistryError.unknownInference(id)
            }
            return binding
        }
    }

    public struct Agents: Sendable {
        fileprivate let entries: [AgentIdentifier: AgentBinding]
        public var definitions: [AgentDefinition] {
            entries.values.map(\.definition)
                .sorted { $0.identifier.rawValue < $1.identifier.rawValue }
        }
        public func binding(identifiedBy id: AgentIdentifier) -> AgentBinding? {
            entries[id]
        }
        public func definition(identifiedBy id: AgentIdentifier) -> AgentDefinition? {
            entries[id]?.definition
        }
        public func requireBinding(identifiedBy id: AgentIdentifier) throws -> AgentBinding {
            guard let binding = binding(identifiedBy: id) else {
                throw AgentRegistryError.unknownAgent(id)
            }
            return binding
        }
        public func requireAgent(identifiedBy id: AgentIdentifier) throws -> AgentDefinition {
            try requireBinding(identifiedBy: id).definition
        }
    }

    public mutating func install<T: Tool>(
        _ tool: T,
        modelContract: ToolModelContract? = nil
    ) throws {
        try tools.register(tool, modelContract: modelContract)
    }

    public mutating func install(_ binding: ProgramExecutionBinding) throws {
        guard programEntries[binding.identifier] == nil else {
            throw CapabilityInventoryError.duplicateProgram(binding.identifier)
        }
        programEntries[binding.identifier] = binding
    }

    public mutating func install(_ binding: InferenceBinding) throws {
        guard inferenceEntries[binding.identifier] == nil else {
            throw CapabilityInventoryError.duplicateInference(binding.identifier)
        }
        inferenceEntries[binding.identifier] = binding
    }

    public mutating func install(_ adapter: any InferenceAdapter) throws {
        try adapters.register(adapter)
    }

    public mutating func install(_ binding: AgentBinding) throws {
        let id = binding.definition.identifier
        guard agentEntries[id] == nil else {
            throw CapabilityInventoryError.duplicateAgent(id)
        }
        agentEntries[id] = binding
    }

    /// Atomic batch installation; rejected batches do not mutate the receiver.
    public mutating func install(_ installation: Installation) throws {
        var candidate = self
        for component in installation.components {
            switch component {
            case .catalog(let contribution):
                candidate.catalog = candidate.catalog + contribution
            case .tools(let registrations):
                for registration in registrations {
                    try registration.apply(into: &candidate.tools)
                }
            case .programs(let bindings):
                for binding in bindings { try candidate.install(binding) }
            case .inferences(let bindings):
                for binding in bindings { try candidate.install(binding) }
            case .agents(let bindings):
                for binding in bindings { try candidate.install(binding) }
            case .adapters(let adapters):
                for adapter in adapters { try candidate.install(adapter) }
            case .launches, .gateways, .modelProviders:
                throw CapabilityInventoryError.notCapabilityInstallation
            }
        }
        self = candidate
    }
}
