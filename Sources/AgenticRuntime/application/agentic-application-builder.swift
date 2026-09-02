import Agentic
import AgenticExecution

public enum AgenticApplicationComponent:
    Sendable
{
    case tools([AgentToolRegistration])
    case skills([AgentSkillRegistration])
    case adapters([AgentModelAdapterRegistration])
    case modelProviders([any AgentModelProvider])
    case voiceInput(any VoiceInputProvider)
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
        _ expression: AgentModelAdapterRegistration
    ) -> [AgenticApplicationComponent] {
        [
            .adapters(
                [
                    expression,
                ]
            ),
        ]
    }

    public static func buildExpression(
        _ expression: [AgentModelAdapterRegistration]
    ) -> [AgenticApplicationComponent] {
        [
            .adapters(
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

public func modelProvider(
    _ provider: any AgentModelProvider
) -> AgenticApplicationComponent {
    .modelProviders(
        [
            provider,
        ]
    )
}


public func voiceInput(
    _ provider: any VoiceInputProvider
) -> AgenticApplicationComponent {
    .voiceInput(
        provider
    )
}
