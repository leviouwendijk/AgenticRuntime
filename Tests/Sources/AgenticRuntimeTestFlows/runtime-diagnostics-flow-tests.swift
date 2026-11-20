import Agentic
import AgenticRuntime
import TestFlows

private struct RuntimeDiagnosticsProgramFixture: Program {
    typealias Input = String
    typealias Output = String

    static let definition = ProgramDefinition(
        identifier: ProgramIdentifier(
            rawValue: "fixture.runtime_diagnostics.program"
        ),
        purpose: "Proves Runtime diagnostics report installed Programs."
    )

    func run(
        _ input: Input,
        in _: ProgramContext
    ) async throws -> Output {
        input
    }
}

private enum RuntimeDiagnosticsAgentFixture: Agent {
    typealias Input = String
    typealias Output = String

    static let purpose =
        "Proves Runtime diagnostics report Agent capability realization."

    static let capabilities = AgentCapabilities(
        available: .init(
            programs: .init(
                members: [
                    RuntimeDiagnosticsProgramFixture.definition.identifier,
                ]
            )
        ),
        visible: .init(
            programs: .init(
                members: [
                    RuntimeDiagnosticsProgramFixture.definition.identifier,
                ]
            )
        )
    )

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(
            rawValue: "fixture.runtime_diagnostics.agent"
        ),
        purpose: purpose,
        capabilities: capabilities
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runRuntimeDiagnostics()
        async throws
        -> [TestDiagnostic]
    {
        let application = Agentic.application(
            "fixture.runtime_diagnostics"
        ) {
            install(
                RuntimeDiagnosticsProgramFixture()
            )
            install(
                RuntimeDiagnosticsAgentFixture.self
            )
        }

        let runtime = try await AgenticRuntime(
            application: application
        )
        let diagnostics = try runtime.diagnostics()
        let agent = try runtime.diagnostics(
            for: RuntimeDiagnosticsAgentFixture
                .definition
                .identifier
        )

        try Expect.equal(
            diagnostics.application,
            application.identifier,
            "diagnostics retain application identity"
        )
        try Expect.equal(
            diagnostics.installed.programs,
            [
                RuntimeDiagnosticsProgramFixture.definition.identifier,
            ],
            "diagnostics expose executable installed Programs"
        )
        try Expect.equal(
            diagnostics.installed.agents,
            [
                RuntimeDiagnosticsAgentFixture.definition.identifier,
            ],
            "diagnostics expose installed Agents"
        )
        try Expect.equal(
            diagnostics.modelCallable.programs,
            [],
            "Programs are not reported model-callable before Program projection exists"
        )
        try Expect.equal(
            diagnostics.modelCallable.agents,
            [],
            "Agents are not reported model-callable before delegation projection exists"
        )
        try Expect.equal(
            agent.available.programs,
            [
                RuntimeDiagnosticsProgramFixture.definition.identifier,
            ],
            "Agent diagnostics expose effective available Programs"
        )
        try Expect.equal(
            agent.visible.programs,
            [
                RuntimeDiagnosticsProgramFixture.definition.identifier,
            ],
            "Agent diagnostics expose effective visible Programs"
        )
        try Expect.equal(
            diagnostics.warnings.contains(
                .programs_not_model_callable
            ),
            true,
            "diagnostics surface installed Programs that are not yet model-callable"
        )
        try Expect.equal(
            diagnostics.warnings.contains(
                .agents_not_model_callable
            ),
            true,
            "diagnostics surface installed Agents that are not yet model-callable"
        )

        return [
            .field(
                "installed_programs",
                String(
                    diagnostics.installed.programs.count
                )
            ),
            .field(
                "installed_agents",
                String(
                    diagnostics.installed.agents.count
                )
            ),
            .field(
                "visible_programs",
                String(
                    agent.visible.programs.count
                )
            ),
        ]
    }
}
