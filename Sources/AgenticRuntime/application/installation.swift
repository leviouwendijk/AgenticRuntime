import Agentic

private final class DomainSink:
    DomainInstallation.Sink
{
    var installation = Installation.none

    func install<T: Tool>(
        _ tool: T,
        modelContract: ToolModelContract?
    ) {
        installation = installation + .init(
            components: [
                .tools(
                    [
                        .tool(
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
        installation = installation + .init(
            components: [
                .inferences([InferenceBinding(inference)]),
            ]
        )
    }

    func install<A: Agent>(
        _ agent: A.Type
    ) {
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

public func install<ToolType: Tool>(
    _ tool: ToolType,
    modelContract: ToolModelContract? = nil
) -> Installation {
    install(
        [
            AgentToolRegistration.tool(
                tool,
                modelContract: modelContract
            ),
        ]
    )
}

public func install(
    _ provider: any AgentToolProvider
) -> Installation {
    install(
        [
            AgentToolRegistration.provider(
                provider
            ),
        ]
    )
}

public func install(
    _ registrations: [AgentToolRegistration]
) -> Installation {
    .init(
        components: [
            .tools(
                registrations
            ),
        ]
    )
}

public func install(
    _ skill: AgentSkill
) -> Installation {
    install(
        [
            AgentSkillRegistration.skill(
                skill
            ),
        ]
    )
}

public func install(
    _ draft: AgentSkillDraft
) -> Installation {
    install(
        [
            AgentSkillRegistration.skill(
                draft
            ),
        ]
    )
}

public func install(
    _ provider: any AgentSkillProvider
) -> Installation {
    install(
        [
            AgentSkillRegistration.provider(
                provider
            ),
        ]
    )
}

public func install(
    _ registrations: [AgentSkillRegistration]
) -> Installation {
    .init(
        components: [
            .skills(
                registrations
            ),
        ]
    )
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
