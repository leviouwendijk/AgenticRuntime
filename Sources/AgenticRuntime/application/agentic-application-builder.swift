import Agentic
import AgenticExecution
import AgenticPrograms

public enum AgenticApplicationComponent:
    Sendable
{
    case tools([AgentToolRegistration])
    case skills([AgentSkillRegistration])
    case programs([AgentRuntimeProgramRegistration])
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
        _ registrations: [AgentRuntimeProgramRegistration]...
    ) -> [AgentRuntimeProgramRegistration] {
        registrations.flatMap {
            $0
        }
    }

    public static func buildExpression<Program: AgentProgram>(
        _ program: Program
    ) -> [AgentRuntimeProgramRegistration] {
        [
            AgentRuntimeProgramRegistration(
                program
            ),
        ]
    }

    public static func buildExpression(
        _ registration: AgentRuntimeProgramRegistration
    ) -> [AgentRuntimeProgramRegistration] {
        [
            registration,
        ]
    }

    public static func buildExpression(
        _ registrations: [AgentRuntimeProgramRegistration]
    ) -> [AgentRuntimeProgramRegistration] {
        registrations
    }

    public static func buildOptional(
        _ registrations: [AgentRuntimeProgramRegistration]?
    ) -> [AgentRuntimeProgramRegistration] {
        registrations ?? []
    }

    public static func buildEither(
        first registrations: [AgentRuntimeProgramRegistration]
    ) -> [AgentRuntimeProgramRegistration] {
        registrations
    }

    public static func buildEither(
        second registrations: [AgentRuntimeProgramRegistration]
    ) -> [AgentRuntimeProgramRegistration] {
        registrations
    }

    public static func buildArray(
        _ registrations: [[AgentRuntimeProgramRegistration]]
    ) -> [AgentRuntimeProgramRegistration] {
        registrations.flatMap {
            $0
        }
    }

    public static func buildLimitedAvailability(
        _ registrations: [AgentRuntimeProgramRegistration]
    ) -> [AgentRuntimeProgramRegistration] {
        registrations
    }
}

public func programs(
    @AgenticApplicationProgramBuilder
    _ content: () -> [AgentRuntimeProgramRegistration]
) -> AgenticApplicationComponent {
    .programs(
        content()
    )
}

public func program<Program: AgentProgram>(
    _ program: Program,
    realization: AgentProgramRealization<Program>? = nil
) -> AgentRuntimeProgramRegistration {
    AgentRuntimeProgramRegistration(
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
