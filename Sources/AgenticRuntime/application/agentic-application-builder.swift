import Agentic

public enum AgenticApplicationComponent:
    Sendable
{
    case catalog(Catalog)
    case tools([AgentToolRegistration])
    case skills([AgentSkillRegistration])
    case programs([ProgramExecutionBinding])
    case inferences([InferenceBinding])
    case adapters([any InferenceAdapter])
    case agents([AgentBinding])
    case launches([ApplicationLaunchEntry])
    case gateways([AgentModelGatewayFactory])
    case modelProviders([any AgentModelProvider])
}

@resultBuilder
public enum AgenticApplicationBuilder {
    public static func buildBlock(
        _ components: [AgenticApplicationComponent]...
    ) -> [AgenticApplicationComponent] {
        components.flatMap {
            $0
        }
    }

    public static func buildExpression(
        _ expression: AgenticApplicationComponent
    ) -> [AgenticApplicationComponent] {
        [
            expression,
        ]
    }

    public static func buildExpression(
        _ expression: [AgenticApplicationComponent]
    ) -> [AgenticApplicationComponent] {
        expression
    }

    public static func buildExpression(
        _ expression: Installation
    ) -> [AgenticApplicationComponent] {
        expression.components
    }

    public static func buildExpression(
        _ expression: [AgentToolRegistration]
    ) -> [AgenticApplicationComponent] {
        [
            .tools(
                expression
            ),
        ]
    }

    public static func buildExpression(
        _ expression: [AgentSkillRegistration]
    ) -> [AgenticApplicationComponent] {
        [
            .skills(
                expression
            ),
        ]
    }

    public static func buildExpression(
        _ expression: AgentModelGatewayFactory
    ) -> [AgenticApplicationComponent] {
        [
            .gateways(
                [
                    expression,
                ]
            ),
        ]
    }

    public static func buildExpression(
        _ expression: [AgentModelGatewayFactory]
    ) -> [AgenticApplicationComponent] {
        [
            .gateways(
                expression
            ),
        ]
    }

    public static func buildOptional(
        _ component: [AgenticApplicationComponent]?
    ) -> [AgenticApplicationComponent] {
        component ?? []
    }

    public static func buildEither(
        first component: [AgenticApplicationComponent]
    ) -> [AgenticApplicationComponent] {
        component
    }

    public static func buildEither(
        second component: [AgenticApplicationComponent]
    ) -> [AgenticApplicationComponent] {
        component
    }

    public static func buildArray(
        _ components: [[AgenticApplicationComponent]]
    ) -> [AgenticApplicationComponent] {
        components.flatMap {
            $0
        }
    }

    public static func buildLimitedAvailability(
        _ component: [AgenticApplicationComponent]
    ) -> [AgenticApplicationComponent] {
        component
    }
}

@resultBuilder
public enum AgenticApplicationProgramBuilder {
    public static func buildBlock(
        _ registrations: [ProgramExecutionBinding]...
    ) -> [ProgramExecutionBinding] {
        registrations.flatMap {
            $0
        }
    }

    public static func buildExpression<ProgramType: Program>(
        _ program: ProgramType
    ) -> [ProgramExecutionBinding] {
        [
            ProgramExecutionBinding(
                program
            ),
        ]
    }

    public static func buildExpression(
        _ registration: ProgramExecutionBinding
    ) -> [ProgramExecutionBinding] {
        [
            registration,
        ]
    }

    public static func buildExpression(
        _ registrations: [ProgramExecutionBinding]
    ) -> [ProgramExecutionBinding] {
        registrations
    }

    public static func buildOptional(
        _ registrations: [ProgramExecutionBinding]?
    ) -> [ProgramExecutionBinding] {
        registrations ?? []
    }

    public static func buildEither(
        first registrations: [ProgramExecutionBinding]
    ) -> [ProgramExecutionBinding] {
        registrations
    }

    public static func buildEither(
        second registrations: [ProgramExecutionBinding]
    ) -> [ProgramExecutionBinding] {
        registrations
    }

    public static func buildArray(
        _ registrations: [[ProgramExecutionBinding]]
    ) -> [ProgramExecutionBinding] {
        registrations.flatMap {
            $0
        }
    }

    public static func buildLimitedAvailability(
        _ registrations: [ProgramExecutionBinding]
    ) -> [ProgramExecutionBinding] {
        registrations
    }
}

public func programs(
    @AgenticApplicationProgramBuilder
    _ content: () -> [ProgramExecutionBinding]
) -> AgenticApplicationComponent {
    .programs(
        content()
    )
}

public func program<ProgramType: Program>(
    _ program: ProgramType,
    realization: ProgramRealization<ProgramType>? = nil
) -> ProgramExecutionBinding {
    ProgramExecutionBinding(
        program,
        defaultRealization: realization
    )
}

@resultBuilder
public enum ApplicationLaunchBuilder {
    public static func buildBlock(
        _ entries: [ApplicationLaunchEntry]...
    ) -> [ApplicationLaunchEntry] {
        entries.flatMap {
            $0
        }
    }

    public static func buildExpression(
        _ entry: ApplicationLaunchEntry
    ) -> [ApplicationLaunchEntry] {
        [
            entry,
        ]
    }

    public static func buildExpression(
        _ entries: [ApplicationLaunchEntry]
    ) -> [ApplicationLaunchEntry] {
        entries
    }

    public static func buildOptional(
        _ entries: [ApplicationLaunchEntry]?
    ) -> [ApplicationLaunchEntry] {
        entries ?? []
    }

    public static func buildEither(
        first entries: [ApplicationLaunchEntry]
    ) -> [ApplicationLaunchEntry] {
        entries
    }

    public static func buildEither(
        second entries: [ApplicationLaunchEntry]
    ) -> [ApplicationLaunchEntry] {
        entries
    }

    public static func buildArray(
        _ entries: [[ApplicationLaunchEntry]]
    ) -> [ApplicationLaunchEntry] {
        entries.flatMap {
            $0
        }
    }

    public static func buildLimitedAvailability(
        _ entries: [ApplicationLaunchEntry]
    ) -> [ApplicationLaunchEntry] {
        entries
    }
}

public func launches(
    @ApplicationLaunchBuilder
    _ content: () -> [ApplicationLaunchEntry]
) -> AgenticApplicationComponent {
    .launches(
        content()
    )
}

public func agent<AgentType: Agent>(
    _ agent: AgentType.Type,
    identifier: ApplicationLaunchIdentifier? = nil,
    title: String? = nil,
    subtitle: String? = nil
) -> ApplicationLaunchEntry {
    let definition = agent.definition

    return .init(
        identifier:
            identifier
            ?? .init(
                rawValue:
                    definition
                    .identifier
                    .rawValue
            ),
        title: title,
        subtitle: subtitle,
        launch: .agent(
            definition.identifier
        )
    )
}

public func program<ProgramType: Program>(
    _ program: ProgramType.Type,
    identifier: ApplicationLaunchIdentifier? = nil,
    title: String? = nil,
    subtitle: String? = nil
) -> ApplicationLaunchEntry {
    let definition = program.definition

    return .init(
        identifier:
            identifier
            ?? .init(
                rawValue:
                    definition
                    .identifier
                    .rawValue
            ),
        title: title,
        subtitle: subtitle,
        launch: .program(
            definition.identifier
        )
    )
}

public func modelProvider(
    _ provider: any AgentModelProvider
) -> AgenticApplicationComponent {
    .modelProviders(
        [
            provider,
        ]
    )
}
