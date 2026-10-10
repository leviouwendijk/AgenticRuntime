import Agentic
import AgenticRuntime
import Macros
import Primitives
import Schema
import TestFlows

@JSONSchema
private struct ProjectionInput: Sendable, Codable, Hashable {
    let message: String
}

private struct ProjectionProgram: Program {
    typealias Input = ProjectionInput
    typealias Output = JSONValue

    static let definition = ProgramDefinition(
        identifier: "fixture.projection.program",
        purpose: "Return a typed Program response."
    )

    func run(
        _ input: Input,
        in _: ProgramContext
    ) async throws -> Output {
        .string(input.message)
    }
}

private enum ProjectionInference: Inference {
    typealias Input = ProjectionInput
    typealias Output = JSONValue

    static let definition = InferenceDefinition(
        identifier: "fixture.projection.inference",
        purpose: "Classify a typed Inference input."
    )
}

private enum ProjectionChildAgent: Agent {
    typealias Input = ProjectionInput
    typealias Output = JSONValue
    static let purpose = "A child intentionally not projectable before delegation."
    static let definition = AgentDefinition(
        identifier: "fixture.projection.child",
        purpose: purpose
    )
}

private struct ProjectionContractTool: Tool {
    typealias Input = ProjectionInput
    typealias Output = JSONValue

    static let definition = ToolDefinition(
        identifier: "fixture.projection.contract_tool",
        purpose: "Contract metadata fixture.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        .string(input.message)
    }
}

private enum ProjectionCallerAgent: Agent {
    typealias Input = ProjectionInput
    typealias Output = JSONValue
    static let purpose = "Project installed, visible capabilities."
    static let capabilities = AgentCapabilities(
        available: .init(
            programs: .init(members: [ProjectionProgram.definition.identifier]),
            inferences: .init(members: [ProjectionInference.definition.identifier]),
            agents: .init(members: [ProjectionChildAgent.definition.identifier])
        ),
        visible: .init(
            programs: .init(members: [ProjectionProgram.definition.identifier]),
            inferences: .init(members: [ProjectionInference.definition.identifier]),
            agents: .init(members: [ProjectionChildAgent.definition.identifier])
        )
    )
    static let definition = AgentDefinition(
        identifier: "fixture.projection.caller",
        purpose: purpose,
        capabilities: capabilities
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runCapabilityContractAlignment() throws -> [TestDiagnostic] {
        let expectedInput = ProjectionInput.jsonschema.jsonvalue
        let expectedOutput = JSONValue.jsonschema.jsonvalue
        let program = ProgramExecutionBinding(ProjectionProgram())
        let inference = InferenceBinding(ProjectionInference.self)
        let tool = ToolBinding(ProjectionContractTool())
        let hostOnlyTool = ToolBinding(
            ProjectionContractTool(),
            modelContract: .hostOnly
        )
        let agent = ProjectionChildAgent.descriptor
        try Expect.equal(program.reference, ProjectionProgram.reference,
            "Runtime Program execution retains Core bound identity")
        try Expect.equal(inference.reference, ProjectionInference.reference,
            "Runtime Inference storage retains Core bound identity")

        for contract in [
            ProjectionProgram.contract,
            ProjectionInference.contract,
            ProjectionChildAgent.contract,
            ProjectionContractTool.contract,
            program.capabilityContract,
            program.program.capabilityContract,
            inference.capabilityContract,
            tool.capabilityContract,
            hostOnlyTool.capabilityContract,
        ] {
            try Expect.equal(
                contract.input.jsonvalue,
                expectedInput,
                "All capability contracts derive their input schema from Input."
            )
            try Expect.equal(
                contract.output.jsonvalue,
                expectedOutput,
                "All capability contracts derive their output schema from Output."
            )
        }
        try Expect.equal(agent.input, expectedInput,
            "Agent declaration retains typed input schema.")
        try Expect.equal(agent.output, expectedOutput,
            "Agent declaration retains typed output schema.")
        try Expect.equal(program.semanticInputSchema.jsonvalue,
            inference.semanticInputSchema.jsonvalue,
            "Executable Program and Inference expose the same typed input.")
        try Expect.equal(program.modelFacingInputSchema.jsonvalue,
            inference.modelFacingInputSchema.jsonvalue,
            "Program and Inference share the same provider arguments envelope.")
        try Expect.equal(hostOnlyTool.modelFacingInputSchema == nil, true,
            "Host-only Tools never become model-facing through shared metadata.")
        try Expect.equal(tool.modelFacingInputSchema != nil, true,
            "Model-facing Tool retains its distinct optional execution envelope.")
        try Expect.equal(
            tool.modelFacingDescriptor?.modelFunction.input,
            tool.modelFacingDescriptor?.input,
            "Tool projection carries its model schema without Tool risk metadata."
        )
        try Expect.equal(
            tool.modelFacingDescriptor?.modelFunction.name,
            ProjectionContractTool.definition.identifier.rawValue,
            "Actual Tools keep their own provider function names."
        )

        // Discovery is derived from executable registrations, not catalog-only
        // declarations; host-only Tools still retain their exact typed schema.
        var discoveredTools = ToolRegistry()
        try discoveredTools.register(
            ProjectionContractTool(), modelContract: .hostOnly
        )
        let installed = InstalledCapabilities(
            tools: discoveredTools,
            programs: [program],
            inferences: [inference],
            agents: [AgentBinding(ProjectionChildAgent.self)]
        )
        let inspections = installed.capabilityInspections()
        try Expect.equal(inspections.count, 4,
            "All four installed executable families have binding-derived inspection")
        let inspectedTool = try Expect.notNil(
            inspections.first { $0.reference == ProjectionContractTool.reference },
            "The host-only Tool exists as an executable binding"
        )
        try Expect.equal(inspectedTool.input, expectedInput,
            "Host-only Tool inspection retains the semantic input schema")
        try Expect.equal(inspectedTool.output, expectedOutput,
            "Host-only Tool inspection retains the semantic output schema")
        try Expect.equal(inspectedTool.modelInputSchema == nil, true,
            "Inspection does not fabricate a model function for a host-only Tool")
        let inspectedProgram = try Expect.notNil(
            inspections.first { $0.reference == ProjectionProgram.reference },
            "An installed Program has inspection data"
        )
        try Expect.equal(inspectedProgram.input, expectedInput,
            "Program inspection uses the same canonical typed contract")

        return [
            .field("typed_capability_families", "4"),
            .field("single_program_schema_source", "true"),
            .field("host_only_not_projected", "true"),
            .field("agent_runtime_output_unmodified", "true"),
        ]
    }

    static func runModelCapabilityProjection() async throws -> [TestDiagnostic] {
        let application = Agentic.application("fixture.projection") {
            install(ProjectionProgram())
            install(ProjectionInference.self)
            install(ProjectionChildAgent.self)
            install(ProjectionCallerAgent.self)
        }
        let runtime = try await AgenticRuntime(application: application)
        let realization = try runtime.realizeAgent(
            identifiedBy: ProjectionCallerAgent.definition.identifier
        )
        let state = realization.makeCapabilityState()
        let projection = try await runtime.modelProjection(for: state)
        let inventory = CapabilityInventory(installed: runtime.installed, state: state)
        let fromInventory = try await inventory.modelProjection()
        try Expect.equal(
            projection.functions, fromInventory.functions,
            "State and inventory callers share exactly one projection implementation."
        )
        let programTarget = CapabilityInvocation.Target.program(
            ProjectionProgram.definition.identifier
        )
        let inferenceTarget = CapabilityInvocation.Target.inference(
            ProjectionInference.definition.identifier
        )
        let agentTarget = CapabilityInvocation.Target.agent(
            ProjectionChildAgent.definition.identifier
        )

        try Expect.equal(
            projection.entries.count, 2,
            "Only executable model-callable Program and Inference are projected."
        )
        try Expect.equal(
            projection.name(for: agentTarget) == nil, true,
            "Visible Agents must not be advertised until governed delegation exists."
        )
        try Expect.equal(
            projection.functions.map(\.name),
            projection.functions.map(\.name).sorted(),
            "Provider-neutral functions are deterministically sorted."
        )
        try Expect.equal(
            projection.functions.count, projection.entries.count,
            "Each provider function has one exact semantic target binding."
        )

        guard let programName = projection.name(for: programTarget),
              let inferenceName = projection.name(for: inferenceTarget)
        else {
            throw ModelCapabilityProjection.ProjectionError.missingProgram(
                ProjectionProgram.definition.identifier
            )
        }
        try Expect.equal(
            programName != inferenceName, true,
            "Different semantic kinds have distinct provider function names."
        )
        try Expect.equal(
            projection.target(named: programName), programTarget,
            "Transport lookup recovers the exact registered Program identifier."
        )
        try Expect.equal(
            projection.target(named: inferenceName), inferenceTarget,
            "Transport lookup recovers the exact registered Inference identifier."
        )
        try Expect.equal(
            projection.target(named: "not-a-projected-function") == nil, true,
            "Unknown provider function names have no semantic capability target."
        )

        let expectedEnvelope = JSONSchema.object {
            JSONSchema.property(
                "arguments",
                schema: ProjectionInput.jsonschema,
                required: true
            )
        }.jsonvalue
        try Expect.equal(
            projection.functions.allSatisfy { $0.input == expectedEnvelope },
            true,
            "Both schemas derive from typed Input and require arguments."
        )

        await state.hide(.init(programs: [ProjectionProgram.definition.identifier]))
        let hidden = try await runtime.modelProjection(for: state)
        let inventoryAfterHide = try await inventory.modelProjection()
        try Expect.equal(
            hidden.functions, inventoryAfterHide.functions,
            "Inventory and state projections both observe live hidden changes."
        )
        try Expect.equal(
            hidden.name(for: programTarget) == nil, true,
            "Live capability hiding removes a provider-visible Program."
        )
        try Expect.equal(
            hidden.name(for: inferenceTarget), inferenceName,
            "Hiding a Program does not rename an unrelated Inference."
        )
        _ = await state.reveal(
            .init(programs: [ProjectionProgram.definition.identifier])
        )
        let revealed = try await runtime.modelProjection(for: state)
        try Expect.equal(
            revealed.name(for: programTarget), programName,
            "A revealed Program retains its stable provider function name."
        )

        return [
            .field("projected", String(projection.entries.count)),
            .field("agents_hidden_until_delegation", "true"),
            .field("schema_derived_from_input", "true"),
            .field("reveal_preserves_name", "true"),
        ]
    }
}
