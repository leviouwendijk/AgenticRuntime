import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runInstructionSelection() throws -> [TestDiagnostic] {
        let first = InstructionDefinition(
            identifier: "fixture.instructions.first", content: "First", source: "first.md"
        )
        let second = InstructionDefinition(
            identifier: "fixture.instructions.second", content: "Second"
        )
        let catalog = Catalog(declarations: [
            .instruction(first),
            .instruction(second),
        ])
        let selection = try catalog.selectingInstructions([
            second.identifier, first.identifier, second.identifier,
            .init(rawValue: "fixture.instructions.missing"),
        ])
        try Expect.equal(selection.instructions.resolved, "Second\n\nFirst")
        try Expect.equal(selection.instructions.references.map(\.identifier), [
            second.identifier, first.identifier,
        ])
        try Expect.equal(selection.instructions.references.last?.source, "first.md")
        try Expect.equal(selection.missingIdentifiers.map(\.rawValue), [
            "fixture.instructions.missing",
        ])
        try Expect.equal(catalog.tools.count, 0)
        try Expect.equal(catalog.programs.count, 0)
        try Expect.equal(catalog.inferences.count, 0)
        try Expect.equal(catalog.agents.count, 0)
        let installed = InstalledCapabilities(catalog: catalog)
        try Expect.equal(installed.capabilityInspections().count, 0)
        try Expect.equal(installed.capabilities.tools.count, 0)
        var rejected = false
        do {
            _ = try Catalog(declarations: [
                .instruction(first),
                .instruction(.init(identifier: first.identifier, content: "Other")),
            ]).selectingInstructions([first.identifier])
        } catch InstructionSelectionError.conflictingDefinitions(let identifier) {
            rejected = true
            try Expect.equal(identifier, first.identifier)
        }
        try Expect.equal(rejected, true)
        return []
    }
}