import Agentic
import AgenticRuntime
import Macros
import Primitives
import Schema
import TestFlows

@JSONSchema
private struct InventoryInput: Sendable, Codable, Hashable {
    let value: String
}

private struct InventoryTool: Tool {
    typealias Input = InventoryInput
    typealias Output = InventoryInput

    static let definition = ToolDefinition(
        identifier: "fixture.inventory.late_tool",
        purpose: "A tool installed during the Agent lifetime.",
        risk: .observe
    )

    func call(_ input: Input, in _: ToolContext) async throws -> Output {
        input
    }
}

private struct InventoryProgram: Program {
    typealias Input = InventoryInput
    typealias Output = JSONValue

    static let definition = ProgramDefinition(
        identifier: "fixture.inventory.late_program",
        purpose: "A program installed during the Agent lifetime."
    )

    func run(_ input: Input, in _: ProgramContext) async throws -> Output {
        .string(input.value)
    }
}

private enum InventoryInference: Inference {
    typealias Input = InventoryInput
    typealias Output = JSONValue

    static let definition = InferenceDefinition(
        identifier: "fixture.inventory.late_inference",
        purpose: "An inference installed during the Agent lifetime."
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runLiveCapabilityInventory() async throws -> [TestDiagnostic] {
        let state = AgentCapabilityState(
            installed: AgentCapabilitySet.none,
            available: AgentCapabilitySet.none,
            visible: AgentCapabilitySet.none
        )
        let inventory = CapabilityInventory(state: state)
        let toolID = InventoryTool.definition.identifier
        let programID = InventoryProgram.definition.identifier
        let inferenceID = InventoryInference.definition.identifier
        let selection = AgentCapabilitySet(
            tools: [toolID], programs: [programID], inferences: [inferenceID]
        )
        let original = await inventory.snapshot()
        try Expect.equal(original.installed, .none, "Initially empty.")

        _ = try await inventory.install(InventoryTool())
        _ = try await inventory.install(ProgramExecutionBinding(InventoryProgram()))
        _ = try await inventory.install(InferenceBinding(InventoryInference.self))
        let installed = await inventory.snapshot()
        try Expect.equal(installed.installed, selection, "Install adds executables.")
        try Expect.equal(installed.available, .none, "Install does not enable.")
        try Expect.equal(installed.visible, .none, "Install does not expose.")

        do {
            _ = try await inventory.expose(selection)
            try Expect.equal(false, true, "Cannot expose before enable.")
        } catch AgentCapabilityMutationError.notEnabled {
        }

        _ = try await inventory.enable(selection)
        let enabled = await inventory.snapshot()
        try Expect.equal(enabled.available, selection, "Explicitly enabled.")
        try Expect.equal(enabled.visible, .none, "Enabled need not be exposed.")

        _ = try await inventory.expose(selection)
        let exposed = await inventory.snapshot()
        try Expect.equal(exposed.visible, selection, "Expose the enabled subset.")
        let tools = await inventory.tools()
        let call = ToolCall(
            id: "inventory_probe",
            tool: toolID,
            input: try JSONCoding.default.value(InventoryInput(value: "success"))
        )
        let executed = try await tools.call(call, workspace: nil)
        let decoded = try executed.result.output.decode(InventoryInput.self)
        try Expect.equal(decoded.value, "success", "The new Tool is executable.")

        let runtime = try await AgenticRuntime(
            application: Agentic.application("inventory-mutation-flow") {}
        )
        let projection = try await runtime.modelProjection(for: inventory)
        try Expect.equal(projection.functions.count, 3,
            "All three installed, enabled, visible families are projected.")

        let parsed = try InventoryTool.Request(parsing: CapabilityCall.Raw(
            id: "inventory_typed_request",
            capability: InventoryTool.reference,
            input: try JSONCoding.default.value(InventoryInput(value: "typed"))
        ))
        try Expect.equal(parsed.input.value, "typed", "Raw to Request parses once.")

        _ = await inventory.disable(selection)
        let revoked = await inventory.snapshot()
        try Expect.equal(revoked.available, .none, "Disable revokes authority.")
        try Expect.equal(revoked.visible, .none, "Disable also hides.")

        let dispatcher = CapabilityDispatcher(
            runtime: runtime,
            capabilityState: state,
            inventory: inventory
        )
        do {
            _ = try await dispatcher.invoke(
                .tool(call),
                origin: .program
            )
            try Expect.equal(false, true, "A revoked Tool must not execute.")
        } catch CapabilityInvocationError.notAvailable(let target) {
            try Expect.equal(target, .tool(toolID), "Revocation is enforced by dispatch.")
        }

        return [
            .field("installed", "3"),
            .field("projected", String(projection.functions.count)),
            .field("revoked", "true"),
        ]
    }
}
