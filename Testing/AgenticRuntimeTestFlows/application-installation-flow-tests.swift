import Agentic
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
        in _: ToolContext
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

private struct DomainAdapterFixtureInference: Inference {
    typealias Input = String
    typealias Output = String
    static let definition = InferenceDefinition(
        identifier: "fixture.domain_adapter_inference",
        purpose: "Typed adapter Domain installation smoke test."
    )
}

@Domain
private enum AdapterInstallationDomain {}

extension AdapterInstallationDomain.Adapters {
    @Adapter
    struct DomainEcho: InferenceAdapterFor {
        typealias Target = DomainAdapterFixtureInference
        func prepare(
            input: String,
            realization _: InferenceRealizationConfiguration
        ) throws -> PreparedInference<String> {
            PreparedInference(
                adaptation: .init(request: AgentRequest(messages: [])),
                decode: { _ in input }
            )
        }
    }
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
        let adapterInstallation = install(NativeStructuredAdapter())
        let derivedAdapterInstallation = install(AdapterInstallationDomain.self)

        let preset =
            toolInstallation
            + programInstallation
            + agentInstallation
            + adapterInstallation
            + derivedAdapterInstallation

        let application = Agentic.application(
            "fixture.installation_composition"
        ) {
            Installation.none + preset

            launches {
                agent(
                    InstallationAgentFixture.self,
                    identifier: .init(
                        rawValue: "coding"
                    ),
                    title: "Coding"
                )
                program(
                    InstallationProgramFixture.self,
                    identifier: .init(
                        rawValue: "program"
                    ),
                    title: "Program"
                )
            }
        }

        try Expect.equal(
            application.toolRegistrations.count,
            1,
            "Installation composition contributes granular Tool registrations"
        )
        try Expect.equal(
            application.programBindings.count,
            1,
            "Installation composition contributes granular Program registrations"
        )
        try Expect.equal(
            application.agentBindings.map(\.reference),
            [InstallationAgentFixture.reference],
            "Installation composition retains executable Agent bindings"
        )
        try Expect.equal(
            application.agentDefinitions,
            [InstallationAgentFixture.definition],
            "Agent definitions are a view derived from installed bindings"
        )
        try Expect.equal(
            application.launchEntries.count,
            2,
            "Application preserves curated launch entries separately from installation"
        )
        try Expect.equal(
            application.launchEntries.map(\.launch),
            [
                .agent(
                    InstallationAgentFixture.definition.identifier
                ),
                .program(
                    InstallationProgramFixture.definition.identifier
                ),
            ],
            "Launch entries preserve their typed Agent and Program targets"
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
            wrappedApplication.programBindings.count,
            application.programBindings.count,
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
        try Expect.equal(runtime.adapters.count, 2,
            "Explicit and @Adapter domain-derived adapters both install")
        try Expect.true(
            application.catalog.adapters.contains(where: {
                $0.identifier == AdapterInstallationDomain.Adapters.DomainEcho.definition.identifier
            }),
            "Domain adapter discovered without manually maintained registries"
        )
        try Expect.equal(runtime.installed.capabilities.inferences.count, 0,
            "Installing an adapter does not implicitly install an Inference")

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
        try Expect.equal(
            runtime.agents.definition(
                identifiedBy:
                    InstallationAgentFixture
                    .definition
                    .identifier
            ) != nil,
            true,
            "Runtime materializes an installed Agent definition into AgentRegistry"
        )
        try Expect.equal(
            runtime.installed.capabilities.programs,
            [InstallationProgramFixture.definition.identifier],
            "Materialized installation is the authoritative executable Program index"
        )
        try Expect.equal(
            runtime.installed.program(InstallationProgramFixture.definition.identifier) != nil,
            true,
            "Execution binding resolves directly from the application installation"
        )
        let agentInventory = CapabilityInventory(
            installed: runtime.installed,
            state: AgentCapabilityState(installed: runtime.installed.capabilities)
        )
        let inheritedProgram = await agentInventory.program(
            InstallationProgramFixture.definition.identifier
        )
        try Expect.equal(
            inheritedProgram != nil,
            true,
            "Agent inventory resolves a shared application binding"
        )
        try Expect.equal(
            runtime.launches,
            application.launchEntries,
            "Runtime validates and preserves application launch entries"
        )

        let invalidApplication = Agentic.application(
            "fixture.invalid_agent_launch"
        ) {
            launches {
                agent(
                    InstallationAgentFixture.self
                )
            }
        }

        do {
            _ = try await AgenticRuntime(
                application: invalidApplication
            )

            fatalError(
                "Expected Runtime to reject a launch entry for an uninstalled Agent."
            )
        } catch let error as ApplicationLaunchResolutionError {
            switch error {
            case .agentNotInstalled(let identifier):
                try Expect.equal(
                    identifier,
                    InstallationAgentFixture.definition.identifier,
                    "Runtime reports the uninstalled Agent referenced by a launch entry"
                )

            case .duplicateIdentifier,
                 .programNotInstalled:
                fatalError(
                    "Expected uninstalled Agent launch failure, got \(error)."
                )
            }
        }

        return [
            .field(
                "tools",
                String(application.toolRegistrations.count)
            ),
            .field(
                "programs",
                String(application.programBindings.count)
            ),
            .field(
                "agents",
                String(application.agentDefinitions.count)
            ),
            .field(
                "launches",
                String(application.launchEntries.count)
            ),
        ]
    }
}
