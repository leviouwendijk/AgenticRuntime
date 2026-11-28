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
        in _: CapabilityContext
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

/// Records the tools of each request it answers, then ends the turn.
private actor ContextAmbientRequests {
    var tools: [[String]] = []
    func record(_ names: [String]) { tools.append(names) }
}

private struct ContextAmbientInvoker: AgentModelInvoking {
    let requests: ContextAmbientRequests

    func buffered(_ invocation: AgentModelInvocation) async throws -> AgentModelInvocation.Result {
        await requests.record(invocation.request.tools.map(\.name))
        let response = AgentResponse(message: Message(role: .assistant, text: "done"), stopReason: .end_turn)
        let route = AgentModelRoute(
            purpose: invocation.selection.purpose,
            profile: AgentModelProfile(
                identifier: "fixture.context_ambient.profile",
                gatewayIdentifier: "fixture.context_ambient.gateway",
                model: "fixture",
                purposes: [invocation.selection.purpose],
                capabilities: [.text]
            )
        )
        return AgentModelInvocation.Result(
            response: response,
            route: AgentModelRouteRecord(
                route: route,
                diagnostics: [],
                requestMetadata: invocation.request.metadata,
                responseMetadata: response.metadata,
                usage: response.usage
            )
        )
    }

    func stream(_ invocation: AgentModelInvocation) -> AsyncThrowingStream<AgentModelInvocation.Event, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await buffered(invocation)
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Declares the same tool, and excludes the ambient grant.
private enum ContextAmbientExcludingFixture:
    Agent
{
    typealias Input = ContextAmbientFixtureValue
    typealias Output = ContextAmbientFixtureValue

    static let purpose = "Declares one tool and no context reading."

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(rawValue: "fixture.context_ambient.excluding"),
        purpose: purpose,
        capabilities: AgentCapabilities(
            available: .init(tools: .init(members: [ContextAmbientToolFixture.definition.identifier])),
            visible: .init(tools: .init(members: [ContextAmbientToolFixture.definition.identifier])),
            grants: .except(.ambient)
        )
    )
}

extension AgenticProgramRuntimeFlowTesting {
    /// Every agent may read the owner's context when Context is installed,
    /// whatever it declares: the `ambient` grant, applied before the first
    /// request. Never when it is not installed or the agent excludes it.
    /// Writing stays declared.
    static func runContextAmbientGrant() async throws -> [TestDiagnostic] {
        let declared = ContextAmbientToolFixture.definition.identifier.rawValue
        let reading = [
            Context.Tools.Index.identifier,
            Context.Tools.Read.identifier,
            Context.Tools.Search.identifier,
            Context.Tools.Remember.identifier,
            Context.Tools.Forget.identifier,
        ].map(\.rawValue)

        func opening(
            context: Bool,
            agent: AgentDefinition = ContextAmbientAgentFixture.definition
        ) async throws -> [String] {
            let runtime = try await AgenticRuntime(application: Agentic.application("fixture.context_ambient") {
                install(ContextAmbientToolFixture())
                if context { install(Context.self) }
                install(ContextAmbientAgentFixture.self)
                install(ContextAmbientExcludingFixture.self)
            })
            let requests = ContextAmbientRequests()
            let executor = try runtime.makeAgentExecutor(
                identifiedBy: agent.identifier,
                model: .init(invoker: ContextAmbientInvoker(requests: requests)),
                configuration: .init(runLimits: .init(iterations: 1))
            )
            _ = try await executor.run(
                AgentRequest(messages: [Message(role: .user, text: "Hello.")]),
                sessionID: "context-ambient-\(context)-\(agent.identifier.rawValue)"
            )
            return await requests.tools.first ?? []
        }

        let with = try await opening(context: true)
        try Expect.equal(
            with.filter { $0 == declared || reading.contains($0) }.sorted(),
            ([declared] + reading).sorted(),
            "Context installed: the reading and memory tools are in the opening beside what the agent declares"
        )
        try Expect.false(
            with.contains(Context.Tools.Save.identifier.rawValue),
            "saving is never granted implicitly"
        )
        let without = try await opening(context: false)
        try Expect.false(
            without.contains { reading.contains($0) },
            "Context not installed: nothing is added"
        )
        let excluded = try await opening(context: true, agent: ContextAmbientExcludingFixture.definition)
        try Expect.false(
            excluded.contains { reading.contains($0) },
            "an agent that excludes the ambient grant does not get it"
        )
        try Expect.true(
            excluded.contains(declared),
            "and keeps what it declares"
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
        let services = try CapabilityServices().inserting(store)

        try Expect.true(CapabilityServices().contextEntries == nil, "no store, no message")
        try Expect.true(services.contextEntries == nil, "no entries, no message")

        _ = try store.save(ContextFrame.example, to: "business.frame")
        try Expect.true(services.contextEntries != nil, "entries make a message")
        let context = services.contextEntries!
        try Expect.equal(context.ids, ["business.voice"], "records the always entries it carries")
        try Expect.equal(context.message.role, .system, "as a system message")
        let text = context.message.content.text
        try Expect.true(text.contains("3 context entries") && text.contains("Alex & Sam"), "awareness and always bodies: \(text)")
        try Expect.true(text.contains("REMEMBERING") && text.contains(Context.Tools.Remember.identifier.rawValue), "and how to remember")

        let summary = services.contextSummary
        try Expect.equal(summary?.entries, 3, "diagnostics count entries")
        try Expect.equal(summary?.always, ["business.voice"], "and the always entries")
        try Expect.true((summary?.alwaysTokens ?? 0) > 0, "with their size")
        try Expect.equal(summary?.memories, 0, "no memories yet")

        _ = try store.save("""
            import Context;

            let note: Entry = .{
                .title = "Note",
                .summary = "Learned.",
                .updated = "2026-11-20",
                .source = "session T, 2026-11-20",
                .body = "The fact.",
            };
            """, to: "memories/sbm.frame")
        try Expect.equal(services.contextSummary?.memories, 1, "diagnostics count memories")
        try Expect.equal(services.contextSummary?.oldestMemory, "2026-11-20", "and the oldest")
        return []
    }
}
