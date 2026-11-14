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
        try registry.register(SystemIO.Tools.MutateFiles())
        try registry.register(Standard.Tools.InspectCapability())
        let full = try Expect.notNil(
            try registry.modelFacingDefinitions(
                for: [SystemIO.Tools.MutateFiles.identifier]
            ).first,
            "mutate_files has a model-facing schema"
        )
        let core = full.core

        func size(_ value: some Encodable) throws -> Int {
            try JSONEncoder().encode(value).count
        }
        let fullSize = try size(full)
        let coreSize = try size(core)
        try Expect.true(coreSize * 2 < fullSize, "Core schema is less than half the full one")
        try Expect.true(core.description.contains("inspect_capability"), "Core schema says where the rest is")
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

        // Inspection returns the full contract and reveals a hidden capability.
        let state = AgentCapabilityState(
            installed: .init(tools: [SystemIO.Tools.MutateFiles.identifier, Standard.Tools.InspectCapability.identifier]),
            available: .init(tools: [SystemIO.Tools.MutateFiles.identifier, Standard.Tools.InspectCapability.identifier]),
            visible: .init(tools: [Standard.Tools.InspectCapability.identifier])
        )
        let installed = InstalledCapabilities(tools: registry)
        let context = ToolContext(
            capabilities: state,
            inspections: installed.capabilityInspections(),
            services: try ToolServices().inserting(CapabilityReveal(state))
        )
        let inspected = try await Standard.Tools.InspectCapability().call(
            .init(kind: .tool, identifier: SystemIO.Tools.MutateFiles.identifier.rawValue),
            in: context
        )
        try Expect.true(inspected.revealed, "Inspection reveals an available, hidden capability")
        try Expect.true(
            await state.snapshot().visible.tools.contains(SystemIO.Tools.MutateFiles.identifier),
            "The revealed capability is visible from the next turn"
        )
        let inspectedText = String(decoding: try JSONEncoder().encode(inspected.input), as: UTF8.self)
        try Expect.true(
            inspectedText.contains("Destination path for copy or move."),
            "Inspection returns the full schema"
        )
        return [
            .field("mutate_files_bytes", "\(fullSize) -> \(coreSize)"),
        ]
    }
}
