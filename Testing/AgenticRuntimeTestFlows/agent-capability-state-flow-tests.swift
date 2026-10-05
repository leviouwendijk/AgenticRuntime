import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runAgentCapabilityState()
        async throws -> [TestDiagnostic]
    {
        let installed = AgentCapabilitySet(
            tools: [
                "capability_state.available_tool",
                "capability_state.unavailable_tool",
            ],
            programs: [
                "capability_state.program",
            ],
            inferences: [
                "capability_state.inference",
            ],
            agents: [
                "capability_state.agent",
            ]
        )
        let available = AgentCapabilitySet(
            tools: [
                "capability_state.available_tool",
            ],
            programs: [
                "capability_state.program",
            ],
            inferences: [
                "capability_state.inference",
            ],
            agents: [
                "capability_state.agent",
            ]
        )
        let state = AgentCapabilityState(
            installed: installed,
            available: available,
            visible: AgentCapabilitySet.none
        )
        let initial = await state.snapshot()

        try Expect.equal(
            initial.installed,
            installed,
            "Capability state retains the complete installed Runtime universe."
        )
        try Expect.equal(
            initial.available,
            available,
            "Availability is concrete Agent authority independent of visibility."
        )
        try Expect.equal(
            initial.visible,
            .none,
            "Capabilities may be available without being visible."
        )

        let revealed = await state.reveal(
            .init(
                tools: [
                    "capability_state.available_tool",
                    "capability_state.unavailable_tool",
                ],
                programs: [
                    "capability_state.program",
                ],
                inferences: [
                    "capability_state.inference",
                ],
                agents: [
                    "capability_state.agent",
                ]
            )
        )

        try Expect.equal(
            revealed.tools,
            [
                "capability_state.available_tool",
            ],
            "Reveal cannot promote an installed-but-unavailable Tool."
        )
        try Expect.equal(
            revealed.programs,
            [
                "capability_state.program",
            ],
            "Programs use the same visibility state as Tools."
        )
        try Expect.equal(
            revealed.inferences,
            [
                "capability_state.inference",
            ],
            "Inferences use the same visibility state as Tools."
        )
        try Expect.equal(
            revealed.agents,
            [
                "capability_state.agent",
            ],
            "Agents use the same visibility state as Tools."
        )

        _ = await state.setAvailable(
            .init(
                tools: [
                    "capability_state.available_tool",
                ],
                programs: [
                    "capability_state.program",
                ],
                inferences: [
                    "capability_state.inference",
                ]
            )
        )
        let constrained = await state.snapshot()

        try Expect.equal(
            constrained.available.agents,
            [],
            "Explicit authority mutation may remove Agent availability."
        )
        try Expect.equal(
            constrained.visible.agents,
            [],
            "Removing availability also removes visibility."
        )

        let restored = await state.restore(
            .init(
                installed: .none,
                available: installed,
                visible: installed
            )
        )

        try Expect.equal(
            restored.available,
            installed,
            "Restore re-bounds persisted availability to the current installed universe."
        )
        try Expect.equal(
            restored.visible,
            restored.available,
            "Restore preserves visible ⊆ available."
        )

        return [
            .field(
                "installed_tools",
                String(
                    restored.installed.tools.count
                )
            ),
            .field(
                "available_programs",
                String(
                    restored.available.programs.count
                )
            ),
            .field(
                "visible_agents",
                String(
                    restored.visible.agents.count
                )
            ),
        ]
    }
}
