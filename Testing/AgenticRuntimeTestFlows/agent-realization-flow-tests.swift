import Agentic
import AgenticRuntime
import Macros
import Schema
import TestFlows
import Workspace

@JSONSchema
private struct AgentRealizationFixtureValue:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private enum AgentRealizationFixtureIdentifiers {
    static let unavailableTool = ToolIdentifier(
        rawValue: "fixture.agent_realization.unavailable_tool"
    )
    static let unavailableProgram = ProgramIdentifier(
        rawValue: "fixture.agent_realization.unavailable_program"
    )
    static let unavailableInference = InferenceIdentifier(
        rawValue: "fixture.agent_realization.unavailable_inference"
    )
    static let unavailableAgent = AgentIdentifier(
        rawValue: "fixture.agent_realization.unavailable_agent"
    )
}

private struct AgentRealizationToolFixture:
    Tool
{
    typealias Input = AgentRealizationFixtureValue
    typealias Output = AgentRealizationFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.agent_realization.tool",
        purpose: "Proves installed Tool capability realization.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        input
    }
}

private struct AgentRealizationProgramFixture:
    Program
{
    typealias Input = AgentRealizationFixtureValue
    typealias Output = AgentRealizationFixtureValue

    static let definition = ProgramDefinition(
        identifier: "fixture.agent_realization.program",
        purpose: "Proves installed Program capability realization."
    )

    func run(
        _ input: Input,
        in _: ProgramContext
    ) async throws -> Output {
        input
    }
}

private enum AgentRealizationChildFixture:
    Agent
{
    typealias Input = AgentRealizationFixtureValue
    typealias Output = AgentRealizationFixtureValue

    static let purpose =
        "Installed child Agent available for delegation."

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(
            rawValue: "fixture.agent_realization.child"
        ),
        purpose: purpose
    )
}

private enum AgentRealizationRootFixture:
    Agent
{
    typealias Input = AgentRealizationFixtureValue
    typealias Output = AgentRealizationFixtureValue

    static let purpose =
        "Proves installed Agent realization into runtime authority."

    static let instructions: String? =
        "Use only the capabilities realized for this Agent."

    static let capabilities = AgentCapabilities(
        available: .init(
            tools: .init(
                members: [
                    AgentRealizationToolFixture.definition.identifier,
                    AgentRealizationFixtureIdentifiers.unavailableTool,
                ]
            ),
            programs: .init(
                members: [
                    AgentRealizationProgramFixture.definition.identifier,
                    AgentRealizationFixtureIdentifiers.unavailableProgram,
                ]
            ),
            inferences: .init(
                members: [
                    AgentRealizationFixtureIdentifiers.unavailableInference,
                ]
            ),
            agents: .init(
                members: [
                    AgentRealizationChildFixture.definition.identifier,
                    AgentRealizationFixtureIdentifiers.unavailableAgent,
                ]
            )
        ),
        visible: .init(
            tools: .init(
                members: [
                    AgentRealizationToolFixture.definition.identifier,
                    AgentRealizationFixtureIdentifiers.unavailableTool,
                ]
            ),
            programs: .init(
                members: [
                    AgentRealizationProgramFixture.definition.identifier,
                    AgentRealizationFixtureIdentifiers.unavailableProgram,
                ]
            ),
            inferences: .init(
                members: [
                    AgentRealizationFixtureIdentifiers.unavailableInference,
                ]
            ),
            agents: .init(
                members: [
                    AgentRealizationChildFixture.definition.identifier,
                    AgentRealizationFixtureIdentifiers.unavailableAgent,
                ]
            )
        )
    )

    static let modelSelection = AgentModelSelection(
        purpose: .coder
    )

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(
            rawValue: "fixture.agent_realization.root"
        ),
        purpose: purpose,
        instructions: instructions,
        capabilities: capabilities,
        modelSelection: modelSelection
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runAgentRealization()
        async throws
        -> [TestDiagnostic]
    {
        let application = Agentic.application(
            "fixture.agent_realization"
        ) {
            install(
                AgentRealizationToolFixture()
            )
            install(
                AgentRealizationProgramFixture()
            )
            install(
                AgentRealizationRootFixture.self
            )
            install(
                AgentRealizationChildFixture.self
            )
        }
        let runtime = try await AgenticRuntime(
            application: application
        )
        let realization = try runtime.realizeAgent(
            identifiedBy:
                AgentRealizationRootFixture
                .definition
                .identifier
        )

        try Expect.equal(
            realization.requestedAvailable.tools,
            [
                AgentRealizationToolFixture.definition.identifier,
                AgentRealizationFixtureIdentifiers.unavailableTool,
            ],
            "Semantic resolution preserves authored available Tool identifiers before Runtime intersection"
        )
        try Expect.equal(
            realization.available.tools,
            [
                AgentRealizationToolFixture.definition.identifier,
            ],
            "Runtime availability intersects requested Tools with installed model-facing Tools"
        )
        try Expect.equal(
            realization.available.programs,
            [
                AgentRealizationProgramFixture.definition.identifier,
            ],
            "Runtime availability intersects requested Programs with installed executable Programs"
        )
        try Expect.equal(
            realization.requestedAvailable.inferences,
            [
                AgentRealizationFixtureIdentifiers.unavailableInference,
            ],
            "Semantic resolution retains the authored available Inference request"
        )
        try Expect.equal(
            realization.available.inferences,
            [],
            "Runtime does not promote semantic-only Inference declarations into executable authority"
        )
        try Expect.equal(
            realization.available.agents,
            [
                AgentRealizationChildFixture.definition.identifier,
            ],
            "Runtime availability intersects requested child Agents with installed Agents"
        )
        try Expect.equal(
            realization.installed.tools,
            [
                AgentRealizationToolFixture.definition.identifier,
            ],
            "Agent realization retains the concrete installed Tool universe used to bound authority"
        )
        try Expect.equal(
            realization.requestedVisible.tools,
            [
                AgentRealizationToolFixture.definition.identifier,
                AgentRealizationFixtureIdentifiers.unavailableTool,
            ],
            "Semantic resolution preserves authored visible Tool identifiers before authority bounding"
        )
        try Expect.equal(
            realization.visible.tools,
            [
                AgentRealizationToolFixture.definition.identifier,
            ],
            "Runtime visibility is bounded by realized availability"
        )
        try Expect.equal(
            realization.visible.programs,
            [
                AgentRealizationProgramFixture.definition.identifier,
            ],
            "Program visibility is represented by the same general capability model"
        )
        try Expect.equal(
            realization.visible.inferences,
            [],
            "Inference visibility cannot exceed executable Inference availability"
        )
        try Expect.equal(
            realization.visible.agents,
            [
                AgentRealizationChildFixture.definition.identifier,
            ],
            "Agent visibility is bounded by realized Agent availability"
        )
        try Expect.equal(
            realization.modelSelection,
            AgentRealizationRootFixture.modelSelection,
            "Agent realization preserves authored model selection"
        )
        try Expect.equal(
            realization.instructions,
            AgentRealizationRootFixture.instructions,
            "Agent realization preserves authored instructions"
        )
        let liveState = realization.makeCapabilityState()
        let liveSnapshot = await liveState.snapshot()

        try Expect.equal(
            liveSnapshot.installed,
            realization.installed,
            "Live Agent capability state starts from the realization's installed universe"
        )
        try Expect.equal(
            liveSnapshot.available,
            realization.available,
            "Live Agent capability state starts from realized availability"
        )
        try Expect.equal(
            liveSnapshot.visible,
            realization.visible,
            "Live Agent capability state starts from realized visibility"
        )

        return [
            .field(
                "requested_tools",
                String(
                    realization
                        .requestedAvailable
                        .tools
                        .count
                )
            ),
            .field(
                "available_tools",
                String(
                    realization
                        .available
                        .tools
                        .count
                )
            ),
            .field(
                "visible_tools",
                String(
                    realization
                        .visible
                        .tools
                        .count
                )
            ),
            .field(
                "programs",
                String(
                    realization
                        .available
                        .programs
                        .count
                )
            ),
            .field(
                "agents",
                String(
                    realization
                        .available
                        .agents
                        .count
                )
            ),
            .field(
                "inferences",
                String(
                    realization
                        .available
                        .inferences
                        .count
                )
            ),
        ]
    }
}
