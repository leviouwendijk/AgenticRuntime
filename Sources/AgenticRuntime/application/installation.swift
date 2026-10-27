import Agentic

private final class DomainSink:
    DomainInstallation.Sink
{
    var installation = Installation.none
    private let excluded: Set<CapabilityReference>

    init(excluded: Set<CapabilityReference> = []) {
        self.excluded = excluded
    }

    func install<T: Tool>(
        _ tool: T,
        modelContract: ToolModelContract?
    ) {
        guard !excluded.contains(T.reference) else { return }
        installation = installation + .init(
            components: [
                .tools(
                    [
                        ToolBinding(
                            tool,
                            modelContract: modelContract
                        ),
                    ]
                ),
            ]
        )
    }

    func install<P: Program>(
        _ program: P,
        realization: ProgramRealization<P>?
    ) {
        guard !excluded.contains(P.reference) else { return }
        installation = installation + .init(
            components: [
                .programs(
                    [
                        ProgramExecutionBinding(
                            program,
                            defaultRealization: realization
                        ),
                    ]
                ),
            ]
        )
    }

    func install<I: Inference>(
        _ inference: I.Type
    ) {
        guard !excluded.contains(I.reference) else { return }
        installation = installation + .init(
            components: [
                .inferences([InferenceBinding(inference)]),
            ]
        )
    }

    func install<A: Agent>(
        _ agent: A.Type
    ) {
        guard !excluded.contains(A.reference) else { return }
        installation = installation + .init(
            components: [
                .agents([AgentBinding(agent)]),
            ]
        )
    }

    func install<A: InferenceAdapter>(_ adapter: A) {
        installation = installation + .init(components: [.adapters([adapter])])
    }

    func install<A: InferenceAdapterFor>(_ adapter: A) {
        install(TypedInferenceAdapter(adapter))
    }
}

public struct Installation:
    Sendable
{
    let components: [AgenticApplicationComponent]

    public init() {
        self.components = []
    }

    init(
        components: [AgenticApplicationComponent]
    ) {
        self.components = components
    }

    public static let none = Self()

    public static func + (
        lhs: Self,
        rhs: Self
    ) -> Self {
        .init(
            components:
                lhs.components
                + rhs.components
        )
    }
}

public func install(
    _ installation: Installation
) -> Installation {
    installation
}

public func install(
    _ catalog: Catalog
) -> Installation {
    .init(
        components: [
            .catalog(
                catalog
            ),
        ]
    )
}

public func install<DomainType: Domain>(
    _ domain: DomainType.Type
) -> Installation {
    let sink = DomainSink()

    domain.installation.install(
        into: sink
    )

    return install(
        domain.catalog
    ) + sink.installation
}

/// Configuration is scoped to one Domain installation. Replacements suppress
/// linker-derived defaults, but never alter the Domain catalog or Agent exposure.
public struct DomainInstallationOverrides: Sendable {
    public let replacing: Installation
    public let omitting: AgentCapabilitySet

    public init(
        replacing: Installation = .none,
        omitting: AgentCapabilitySet = .none
    ) {
        self.replacing = replacing
        self.omitting = omitting
    }
}

public enum DomainInstallationOverrideError: Error, Sendable, Equatable {
    case unsupportedReplacement
    case undeclaredCapability(CapabilityReference)
    case duplicateReplacement(CapabilityReference)
}

/// Explicit replacement is resolved before derived construction, avoiding
/// registration collisions with a default-constructible declaration.
/// An injected non-default-constructible declaration also becomes executable.
public func install<DomainType: Domain>(
    _ domain: DomainType.Type,
    overrides: DomainInstallationOverrides
) throws -> Installation {
    let catalog = domain.catalog
    let declared: Set<CapabilityReference> = Set(
        catalog.declarations.compactMap { declaration in
            switch declaration {
            case .tool(let definition):
                return .tool(definition.identifier)
            case .program(let definition):
                return .program(definition.identifier)
            case .inference(let definition):
                return .inference(definition.identifier)
            case .agent(let definition):
                return .agent(definition.identifier)
            case .adapter, .instruction:
                return nil
            }
        }
    )

    let omitted: [CapabilityReference] =
        overrides.omitting.tools.map(CapabilityReference.tool)
        + overrides.omitting.programs.map(CapabilityReference.program)
        + overrides.omitting.inferences.map(CapabilityReference.inference)
        + overrides.omitting.agents.map(CapabilityReference.agent)

    var suppressed = Set<CapabilityReference>()
    for reference in omitted {
        guard declared.contains(reference) else {
            throw DomainInstallationOverrideError.undeclaredCapability(reference)
        }
        suppressed.insert(reference)
    }

    var replaced = Set<CapabilityReference>()
    for component in overrides.replacing.components {
        let references: [CapabilityReference]
        switch component {
        case .tools(let bindings):
            references = bindings.map(\.reference)
        case .programs(let bindings):
            references = bindings.map(\.reference)
        case .inferences(let bindings):
            references = bindings.map(\.reference)
        case .agents(let bindings):
            references = bindings.map(\.reference)
        case .catalog, .toolProviders, .adapters, .launches, .gateways, .modelProviders:
            throw DomainInstallationOverrideError.unsupportedReplacement
        }
        for reference in references {
            guard declared.contains(reference) else {
                throw DomainInstallationOverrideError.undeclaredCapability(reference)
            }
            guard replaced.insert(reference).inserted else {
                throw DomainInstallationOverrideError.duplicateReplacement(reference)
            }
            suppressed.insert(reference)
        }
    }

    let sink = DomainSink(excluded: suppressed)
    domain.installation.install(into: sink)
    return install(catalog) + sink.installation + overrides.replacing
}

public func install<ToolType: Tool>(
    _ tool: ToolType,
    modelContract: ToolModelContract? = nil
) -> Installation {
    install(
        ToolBinding(
            tool,
            modelContract: modelContract
        )
    )
}

/// Providers remain an explicit installation path because they may register
/// multiple Tools and cannot be represented by a single ToolBinding.
public func install(
    _ provider: any AgentToolProvider
) -> Installation {
    .init(components: [.toolProviders([provider])])
}

public func install(
    _ binding: ToolBinding
) -> Installation {
    install([binding])
}

public func install(
    _ bindings: [ToolBinding]
) -> Installation {
    .init(components: [.tools(bindings)])
}

public func install<ProgramType: Program>(
    _ program: ProgramType,
    realization: ProgramRealization<ProgramType>? = nil
) -> Installation {
    install(
        [
            ProgramExecutionBinding(
                program,
                defaultRealization: realization
            ),
        ]
    )
}

public func install(
    _ registration: ProgramExecutionBinding
) -> Installation {
    install(
        [
            registration,
        ]
    )
}

public func install(
    _ registrations: [ProgramExecutionBinding]
) -> Installation {
    .init(
        components: [
            .programs(
                registrations
            ),
        ]
    )
}

/// Install an executable typed Inference separately from its Catalog declaration.
/// This does not change Agent visibility or availability; realization does that.
public func install<InferenceType: Inference>(
    _ inference: InferenceType.Type,
    realization: InferenceRealizationConfiguration? = nil
) -> Installation {
    install(
        InferenceBinding(
            inference,
            defaultRealization: realization
        )
    )
}

public func install(
    _ registration: InferenceBinding
) -> Installation {
    install([registration])
}

public func install(
    _ registrations: [InferenceBinding]
) -> Installation {
    .init(
        components: [
            .inferences(registrations),
        ]
    )
}

/// Adapters are installation infrastructure; this does not grant model exposure.
public func install<A: InferenceAdapter>(_ adapter: A) -> Installation {
    .init(components: [.adapters([adapter])])
}

public func install<A: InferenceAdapterFor>(_ adapter: A) -> Installation {
    install(TypedInferenceAdapter(adapter))
}

public func install<AgentType: Agent>(
    _ agent: AgentType.Type
) -> Installation {
    install(AgentBinding(agent))
}

public func install(
    _ binding: AgentBinding
) -> Installation {
    install([binding])
}

public func install(
    _ bindings: [AgentBinding]
) -> Installation {
    .init(components: [.agents(bindings)])
}
