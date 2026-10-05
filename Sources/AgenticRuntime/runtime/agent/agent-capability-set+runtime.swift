import Agentic

extension AgentCapabilitySet {
    func intersecting(
        _ limit: Self
    ) -> Self {
        let toolIdentifiers = Set(
            limit.tools
        )
        let programIdentifiers = Set(
            limit.programs
        )
        let inferenceIdentifiers = Set(
            limit.inferences
        )
        let agentIdentifiers = Set(
            limit.agents
        )

        return .init(
            tools: tools.filter(
                toolIdentifiers.contains
            ),
            programs: programs.filter(
                programIdentifiers.contains
            ),
            inferences: inferences.filter(
                inferenceIdentifiers.contains
            ),
            agents: agents.filter(
                agentIdentifiers.contains
            )
        )
    }

    func union(
        _ other: Self
    ) -> Self {
        .init(
            tools:
                tools
                + other.tools,
            programs:
                programs
                + other.programs,
            inferences:
                inferences
                + other.inferences,
            agents:
                agents
                + other.agents
        )
    }

    func subtracting(
        _ other: Self
    ) -> Self {
        let toolIdentifiers = Set(
            other.tools
        )
        let programIdentifiers = Set(
            other.programs
        )
        let inferenceIdentifiers = Set(
            other.inferences
        )
        let agentIdentifiers = Set(
            other.agents
        )

        return .init(
            tools: tools.filter {
                !toolIdentifiers.contains(
                    $0
                )
            },
            programs: programs.filter {
                !programIdentifiers.contains(
                    $0
                )
            },
            inferences: inferences.filter {
                !inferenceIdentifiers.contains(
                    $0
                )
            },
            agents: agents.filter {
                !agentIdentifiers.contains(
                    $0
                )
            }
        )
    }
}
