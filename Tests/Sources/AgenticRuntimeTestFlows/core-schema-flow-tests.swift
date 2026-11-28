import Agentic
import AgenticIO
import AgenticRuntime
import AgenticStandard
import Foundation
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runCoreSchemas() async throws -> [TestDiagnostic] {
        var registry = ToolRegistry()
        try registry.register(SystemIO.Tools.Mutate())
        try registry.register(Capabilities.Tools.Inspect())
        let full = try Expect.notNil(
            try registry.modelFacingDefinitions(
                for: [SystemIO.Tools.Mutate.identifier]
            ).first,
            "mutate has a model-facing schema"
        )
        let core = full.core

        func size(_ value: some Encodable) throws -> Int {
            try JSONEncoder().encode(value).count
        }
        let fullSize = try size(full)
        let coreSize = try size(core)
        try Expect.true(coreSize * 4 < fullSize * 3, "Core schema drops at least a quarter")
        try Expect.true(core.description.contains("capabilities_tool_inspect"), "Core schema says where the rest is")
        try Expect.equal(core.core, core, "Projection is idempotent")

        let coreText = String(decoding: try JSONEncoder().encode(core.input), as: UTF8.self)
        try Expect.true(
            coreText.contains("move requires path as the source"),
            "Guidance under required fields is kept"
        )
        try Expect.true(
            !coreText.contains("Destination path for copy or move."),
            "Optional field descriptions are dropped"
        )
        try Expect.true(coreText.contains("\"destination\""), "Optional fields stay named")

        // Inspection returns the full contract and changes nothing.
        let state = AgentCapabilityState(
            installed: .init(tools: [SystemIO.Tools.Mutate.identifier, Capabilities.Tools.Inspect.identifier]),
            available: .init(tools: [SystemIO.Tools.Mutate.identifier, Capabilities.Tools.Inspect.identifier]),
            visible: .init(tools: [Capabilities.Tools.Inspect.identifier])
        )
        let installed = InstalledCapabilities(tools: registry)
        let context = CapabilityContext(
            capabilities: state,
            inspections: installed.capabilityInspections(),
            services: CapabilityServices()
        )
        let inspected = try await Capabilities.Tools.Inspect().call(
            .init(kind: .tool, identifier: SystemIO.Tools.Mutate.identifier.rawValue),
            in: context
        )
        try Expect.false(inspected.wasVisible, "The inspected capability is not among the definitions")
        try Expect.false(
            await state.snapshot().visible.tools.contains(SystemIO.Tools.Mutate.identifier),
            "Inspection does not reveal it"
        )
        let inspectedText = String(decoding: try JSONEncoder().encode(inspected.input), as: UTF8.self)
        try Expect.true(
            inspectedText.contains("Destination path for copy or move."),
            "Inspection returns the full schema"
        )
        // Agents: the delegation envelope survives core form and inspection.
        let agents = InstalledCapabilities(agents: [AgentBinding(CoreSchemaWorker.self)])
        let agentSchema = try Expect.notNil(
            agents.capabilityInspections().first?.modelInputSchema,
            "Inspecting an Agent returns the function the model calls"
        )
        let agentCore = ToolDescriptor(name: "worker", description: "Worker.", input: agentSchema).core
        let agentText = String(decoding: try JSONEncoder().encode(agentCore.input), as: UTF8.self)
        try Expect.true(
            agentText.contains("workspace_scope"),
            "Core form keeps the workspace scope an Agent needs for file access"
        )
        return [
            .field("mutate_files_bytes", "\(fullSize) -> \(coreSize)"),
        ]
    }
}

private enum CoreSchemaWorker: Agent {
    typealias Input = String
    typealias Output = String
    static let purpose = "Implements delegated changes."
    static let definition = AgentDefinition(
        identifier: "fixture.core_schema.worker",
        purpose: purpose
    )
}
