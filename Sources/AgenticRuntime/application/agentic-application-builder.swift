import Agentic
import AgenticExecution

public enum AgenticApplicationComponent:
    Sendable
{
    case catalog(Catalog)
    case tools([AgentToolRegistration])
    case skills([AgentSkillRegistration])
    case programs([ProgramRegistration])
    case agents([AgentDefinition])
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
        _ registrations: [ProgramRegistration]...
    ) -> [ProgramRegistration] {
        registrations.flatMap {
            $0
        }
    }

    public static func buildExpression<ProgramType: Program>(
        _ program: ProgramType
    ) -> [ProgramRegistration] {
        [
            ProgramRegistration(
                program
            ),
        ]
    }

    public static func buildExpression(
        _ registration: ProgramRegistration
    ) -> [ProgramRegistration] {
        [
            registration,
        ]
    }

    public static func buildExpression(
        _ registrations: [ProgramRegistration]
    ) -> [ProgramRegistration] {
        registrations
    }

    public static func buildOptional(
        _ registrations: [ProgramRegistration]?
    ) -> [ProgramRegistration] {
        registrations ?? []
    }

    public static func buildEither(
        first registrations: [ProgramRegistration]
    ) -> [ProgramRegistration] {
        registrations
    }

    public static func buildEither(
        second registrations: [ProgramRegistration]
    ) -> [ProgramRegistration] {
        registrations
    }

    public static func buildArray(
        _ registrations: [[ProgramRegistration]]
    ) -> [ProgramRegistration] {
        registrations.flatMap {
            $0
        }
    }

    public static func buildLimitedAvailability(
        _ registrations: [ProgramRegistration]
    ) -> [ProgramRegistration] {
        registrations
    }
}

public func programs(
    @AgenticApplicationProgramBuilder
    _ content: () -> [ProgramRegistration]
) -> AgenticApplicationComponent {
    .programs(
        content()
    )
}

public func program<ProgramType: Program>(
    _ program: ProgramType,
    realization: ProgramRealization<ProgramType>? = nil
) -> ProgramRegistration {
    ProgramRegistration(
        program,
        defaultRealization: realization
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
