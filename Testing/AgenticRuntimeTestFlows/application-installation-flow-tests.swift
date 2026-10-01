import Agentic
import AgenticExecution
import AgenticRuntime
import Macros
import Schema
import TestFlows
import Workspace

@JSONSchema
private struct InstallationFixtureValue:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct InstallationToolFixture:
    Tool
{
    typealias Input = InstallationFixtureValue
    typealias Output = InstallationFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.installation_tool",
        purpose: "Proves granular Tool installation through Installation.",
        risk: .observe
    )

    func call(
        _ input: Input,
        workspace _: WorkspaceContext?
    ) async throws -> Output {
        input
    }
}

private struct InstallationProgramFixture:
    Program
{
    typealias Input = InstallationFixtureValue
    typealias Output = InstallationFixtureValue

    static let definition = ProgramDefinition(
        identifier: "fixture.installation_program",
        purpose: "Proves granular Program installation through Installation.",
        title: "Installation Program"
    )

    func run(
        _ input: Input,
        in _: ProgramContext
    ) async throws -> Output {
        input
    }
}

private enum InstallationAgentFixture:
    Agent
{
    typealias Input = InstallationFixtureValue
    typealias Output = InstallationFixtureValue

    static let purpose =
        "Proves granular Agent installation through Installation."

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(
            rawValue: "fixture.installation_agent"
        ),
        purpose: purpose
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runApplicationInstallationComposition()
        async throws
        -> [TestDiagnostic]
    {
        let toolInstallation = install(
            InstallationToolFixture()
        )
        let programInstallation = install(
            InstallationProgramFixture()
        )
        let agentInstallation = install(
            InstallationAgentFixture.self
        )

        let preset =
            toolInstallation
            + programInstallation
            + agentInstallation

        let application = Agentic.application(
            "fixture.installation_composition"
        ) {
            Installation.none + preset
        }

        try Expect.equal(
            application.toolRegistrations.count,
            1,
            "Installation composition contributes granular Tool registrations"
        )
        try Expect.equal(
            application.programRegistrations.count,
            1,
            "Installation composition contributes granular Program registrations"
        )
        try Expect.equal(
            application.agentDefinitions,
            [
                InstallationAgentFixture.definition,
            ],
            "Installation composition preserves installed Agent definitions"
        )

        let wrappedApplication = Agentic.application(
            "fixture.installation_passthrough"
        ) {
            install(
                preset
            )
        }

        try Expect.equal(
            wrappedApplication.toolRegistrations.count,
            application.toolRegistrations.count,
            "install(Installation) preserves composed Tool contributions"
        )
        try Expect.equal(
            wrappedApplication.programRegistrations.count,
            application.programRegistrations.count,
            "install(Installation) preserves composed Program contributions"
        )
        try Expect.equal(
            wrappedApplication.agentDefinitions,
            application.agentDefinitions,
            "install(Installation) preserves composed Agent contributions"
        )

        let runtime = try await AgenticRuntime(
            application: application
        )

        try Expect.equal(
            runtime.tools.inspect(
                identifiedBy:
                    InstallationToolFixture
                    .definition.identifier
            ) != nil,
            true,
            "Runtime materializes a Tool contributed through Installation"
        )
        try Expect.equal(
            runtime.programs.definitions.map(\.identifier).contains(
                InstallationProgramFixture.definition.identifier
            ),
            true,
            "Runtime materializes a Program contributed through Installation"
        )

        return [
            .field(
                "tools",
                String(application.toolRegistrations.count)
            ),
            .field(
                "programs",
                String(application.programRegistrations.count)
            ),
            .field(
                "agents",
                String(application.agentDefinitions.count)
            ),
        ]
    }
}
