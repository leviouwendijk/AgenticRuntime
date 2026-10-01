import Agentic
import AgenticExecution

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

public func install<ToolType: Tool>(
    _ tool: ToolType,
    modelContract: AgentToolModelContract? = nil,
    execution: AgentToolExecutionContract = .fixed
) -> Installation {
    install(
        [
            AgentToolRegistration.tool(
                tool,
                modelContract: modelContract,
                execution: execution
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
            ProgramRegistration(
                program,
                defaultRealization: realization
            ),
        ]
    )
}

public func install(
    _ registration: ProgramRegistration
) -> Installation {
    install(
        [
            registration,
        ]
    )
}

public func install(
    _ registrations: [ProgramRegistration]
) -> Installation {
    .init(
        components: [
            .programs(
                registrations
            ),
        ]
    )
}

public func install<AgentType: Agent>(
    _ agent: AgentType.Type
) -> Installation {
    install(
        agent.definition
    )
}

public func install(
    _ definition: AgentDefinition
) -> Installation {
    install(
        [
            definition,
        ]
    )
}

public func install(
    _ definitions: [AgentDefinition]
) -> Installation {
    .init(
        components: [
            .agents(
                definitions
            ),
        ]
    )
}
