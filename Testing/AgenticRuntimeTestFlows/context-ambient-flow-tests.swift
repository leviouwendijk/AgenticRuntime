import Agentic
import AgenticContext
import AgenticRuntime
import Foundation
import Macros
import Schema
import TestFlows

@JSONSchema
private struct ContextAmbientFixtureValue:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct ContextAmbientToolFixture:
    Tool
{
    typealias Input = ContextAmbientFixtureValue
    typealias Output = ContextAmbientFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.context_ambient.tool",
        purpose: "The one tool the fixture agent declares.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        input
    }
}

/// Declares nothing of Context.
private enum ContextAmbientAgentFixture:
    Agent
{
    typealias Input = ContextAmbientFixtureValue
    typealias Output = ContextAmbientFixtureValue

    static let purpose = "Declares one unrelated tool."

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(rawValue: "fixture.context_ambient.agent"),
        purpose: purpose,
        capabilities: AgentCapabilities(
            available: .init(tools: .init(members: [ContextAmbientToolFixture.definition.identifier])),
            visible: .init(tools: .init(members: [ContextAmbientToolFixture.definition.identifier]))
        )
    )
}

extension AgenticProgramRuntimeFlowTesting {
    /// Every agent may read the owner's context when Context is installed,
    /// whatever it declares; never when it is not. Writing stays declared.
    static func runContextAmbientGrant() async throws -> [TestDiagnostic] {
        let reading = [
            Context.Tools.Index.identifier,
            Context.Tools.Read.identifier,
            Context.Tools.Search.identifier,
        ]
        let with = try await AgenticRuntime(application: Agentic.application("fixture.context_ambient") {
            install(ContextAmbientToolFixture())
            install(Context.self)
            install(ContextAmbientAgentFixture.self)
        }).realizeAgent(identifiedBy: ContextAmbientAgentFixture.definition.identifier)
        try Expect.equal(
            with.available.tools,
            [ContextAmbientToolFixture.definition.identifier] + reading,
            "Context installed: the reading tools are available beside what the agent declares"
        )
        try Expect.equal(
            with.visible.tools,
            [ContextAmbientToolFixture.definition.identifier] + reading,
            "and visible"
        )
        try Expect.false(
            with.available.tools.contains(Context.Tools.Save.identifier),
            "saving is never granted implicitly"
        )

        let without = try await AgenticRuntime(application: Agentic.application("fixture.context_ambient_none") {
            install(ContextAmbientToolFixture())
            install(ContextAmbientAgentFixture.self)
        }).realizeAgent(identifiedBy: ContextAmbientAgentFixture.definition.identifier)
        try Expect.equal(
            without.available.tools,
            [ContextAmbientToolFixture.definition.identifier],
            "Context not installed: nothing is added"
        )
        return []
    }

    /// The context message every run receives, and what it records.
    static func runContextEntryMessage() async throws -> [TestDiagnostic] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-context-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Context.Store(
            directory: root.appendingPathComponent("context", isDirectory: true),
            archiveDirectory: root.appendingPathComponent("archive", isDirectory: true)
        )
        let services = try ToolServices().inserting(store)

        try Expect.true(ToolServices().contextEntries == nil, "no store, no message")
        try Expect.true(services.contextEntries == nil, "no entries, no message")

        _ = try store.save(ContextFrame.example, to: "business.frame")
        try Expect.true(services.contextEntries != nil, "entries make a message")
        let context = services.contextEntries!
        try Expect.equal(context.ids, ["business.voice"], "records the always entries it carries")
        try Expect.equal(context.message.role, .system, "as a system message")
        let text = context.message.content.text
        try Expect.true(text.contains("3 context entries") && text.contains("Alex & Sam"), "awareness and always bodies: \(text)")

        let summary = services.contextSummary
        try Expect.equal(summary?.entries, 3, "diagnostics count entries")
        try Expect.equal(summary?.always, ["business.voice"], "and the always entries")
        try Expect.true((summary?.alwaysTokens ?? 0) > 0, "with their size")
        return []
    }
}
