import Agentic
import AgenticContextWindow
@_spi(Testing) import AgenticRuntime
import AgenticStandard
import Foundation
import IO
import Primitives
import Schema
import TestFlows

/// A large result reaches the model as its beginning plus where
/// `read_result` continues; the log keeps it whole, `read_result` pages
/// through it and `search_results` finds a line in it.
extension AgenticProgramRuntimeFlowTesting {
    static func runResultBudget() async throws -> [TestDiagnostic] {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("result-budget-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileSystem.default.remove(root) }
        let log = try Run.Log.Store(storage: .init(root: root)).open(session: "budget")

        let listing = FunctionCall(
            id: "c-list",
            name: BudgetListingTool.definition.identifier.rawValue,
            input: .object(["arguments": .object([:])])
        )
        let page = FunctionCall(
            id: "c-page",
            name: Standard.Tools.ReadResult.identifier.rawValue,
            input: .object(["arguments": .object([
                "call": .string(listing.id),
                "offset": .int(101),
                "limit": .int(3),
            ])])
        )
        let search = FunctionCall(
            id: "c-search",
            name: Standard.Tools.SearchResults.identifier.rawValue,
            input: .object(["arguments": .object([
                "query": .string("line 250"),
            ])])
        )
        let state = BudgetModelState()
        let registry = try ToolRegistry {
            BudgetListingTool()
            Standard.Tools.ReadResult()
            Standard.Tools.SearchResults()
        }
        let tools = [
            BudgetListingTool.definition.identifier,
            Standard.Tools.ReadResult.identifier,
            Standard.Tools.SearchResults.identifier,
        ]
        let executor = AgentExecutor(
            model: .init(invoker: BudgetModelInvoker(state: state, calls: [listing, page, search])),
            configuration: .init(
                runLimits: .init(iterations: 5),
                contextPolicy: .init(resultBudget: 300)
            ),
            tooling: .init(
                registry: registry,
                services: try ToolServices().inserting(log)
            ),
            capabilityState: AgentCapabilityState(
                installed: .init(tools: tools),
                available: .init(tools: tools),
                visible: .init(tools: [BudgetListingTool.definition.identifier])
            ),
            recording: .init(eventSinks: [log.recorder(run: "r1")])
        )
        _ = try await executor.run(
            AgentRequest(messages: [Message(role: .user, text: "List everything.")]),
            sessionID: "budget"
        )
        let invocations = await state.snapshot()
        try Expect.equal(invocations.count, 4, "List, page, search, answer")

        func result(_ id: String, in invocation: AgentModelInvocation) -> FunctionCall.Response? {
            invocation.request.messages.flatMap(\.content.blocks).lazy.compactMap { block in
                guard case .result(let response) = block, response.call.id == id else { return nil }
                return response
            }.first
        }

        let shown = try Expect.notNil(result(listing.id, in: invocations[1]), "The model got the listing")
        let full = BudgetListingTool.text
        try Expect.true(shown.modelText.count < full.count / 4, "The model reads a shortened listing")
        try Expect.true(shown.modelText.hasPrefix("line 1\nline 2\n"), "It starts at the beginning")
        try Expect.true(
            shown.modelText.contains(#"read_result {"call": "c-list", "offset": "#),
            "It says where read_result continues"
        )
        try Expect.equal(shown.output, .int(400), "The structured output is untouched")
        try Expect.true(
            invocations[0].request.tools.contains { $0.name == Standard.Tools.ReadResult.identifier.rawValue },
            "read_result is in the opening set when results can be shortened"
        )
        try Expect.equal(
            invocations[0].request.tools.map(\.name),
            invocations[1].request.tools.map(\.name),
            "so shortening a result leaves the advertised tools unchanged"
        )

        let paged = try Expect.notNil(result(page.id, in: invocations[2]), "The model got the page")
        try Expect.equal(
            paged.modelText,
            "line 101\nline 102\nline 103\n[Lines 101–103 of 400. read_result {\"call\": \"c-list\", \"offset\": 104} continues.]",
            "read_result pages through the full result"
        )
        try Expect.equal(
            try await log.response(call: listing.id)?.modelText,
            full,
            "The log keeps the full result"
        )
        let found = try Expect.notNil(result(search.id, in: invocations[3]), "The model got the search")
        try Expect.equal(
            found.modelText,
            "c-list \(BudgetListingTool.definition.identifier.rawValue) · text\n  250: line 250\n"
                + "read_result {\"call\": \"c-list\", \"segment\": \"text\", \"offset\": 245} reads around a hit.",
            "search_results finds a line the model was never shown, and not in read_result's own page"
        )
        try Expect.equal(
            try await log.responses(limit: 10).map(\.call.id),
            [search.id, page.id, listing.id],
            "The log lists responses newest first"
        )
        return [.field("shown_characters", "\(shown.modelText.count) of \(full.count)")]
    }
}

extension AgenticProgramRuntimeFlowTesting {
    /// Arguments a provider could not parse are answered as a tool error the
    /// model can correct; the run goes on instead of failing.
    static func runMalformedArguments() async throws -> [TestDiagnostic] {
        let name = BudgetListingTool.definition.identifier.rawValue
        let broken = FunctionCall(id: "c-broken", name: name, malformedArguments: #"{"arguments": {"#)
        let retry = FunctionCall(id: "c-retry", name: name, input: .object(["arguments": .object([:])]))
        let state = BudgetModelState()
        let tools = [BudgetListingTool.definition.identifier]
        let executor = AgentExecutor(
            model: .init(invoker: BudgetModelInvoker(state: state, calls: [broken, retry])),
            configuration: .init(runLimits: .init(iterations: 4)),
            tooling: .init(registry: try ToolRegistry { BudgetListingTool() }),
            capabilityState: AgentCapabilityState(
                installed: .init(tools: tools),
                available: .init(tools: tools),
                visible: .init(tools: tools)
            )
        )
        let result = try await executor.run(
            AgentRequest(messages: [Message(role: .user, text: "List everything.")]),
            sessionID: "malformed"
        )
        try Expect.true(result.isCompleted, "The run completes")
        let invocations = await state.snapshot()
        try Expect.equal(invocations.count, 3, "Broken call, retry, answer")
        let answered = try Expect.notNil(
            invocations[1].request.messages.flatMap(\.content.blocks).lazy.compactMap { block -> FunctionCall.Response? in
                guard case .result(let response) = block, response.call.id == broken.id else { return nil }
                return response
            }.first,
            "The broken call is answered"
        )
        try Expect.true(answered.isError, "as an error")
        try Expect.true(answered.modelText.contains("not valid JSON"), "that says why")
        return []
    }
}

private struct BudgetListingInput: Sendable, Codable, JSONSchemaProviding {
    static var jsonschema: JSONSchema { .object {} }
}

private struct BudgetListingTool: Tool {
    typealias Input = BudgetListingInput
    typealias Output = Int

    static let text = (1...400).map { "line \($0)" }.joined(separator: "\n")
    static let definition = ToolDefinition(
        identifier: "fixture.listing",
        purpose: "Lists four hundred lines.",
        risk: .observe
    )

    func preflight(_ input: Input, in context: ToolContext) async throws -> ToolPreflight {
        ToolPreflight(tool: Self.definition.identifier, risk: .observe, summary: "List lines.")
    }

    func call(_ input: Input, in context: ToolContext) async throws -> Int {
        400
    }

    func render(_ output: Int, input: Input) -> String? {
        Self.text
    }
}

private actor BudgetModelState {
    private var invocations: [AgentModelInvocation] = []

    func record(_ invocation: AgentModelInvocation) -> Int {
        invocations.append(invocation)
        return invocations.count - 1
    }

    func snapshot() -> [AgentModelInvocation] {
        invocations
    }
}

private struct BudgetModelInvoker: AgentModelInvoking {
    let state: BudgetModelState
    let calls: [FunctionCall]

    func buffered(_ invocation: AgentModelInvocation) async throws -> AgentModelInvocation.Result {
        let index = await state.record(invocation)
        let response = index < calls.count
            ? AgentResponse(
                message: Message(role: .assistant, content: .init(blocks: [.call(calls[index])])),
                stopReason: .tool_use
            )
            : AgentResponse(message: Message(role: .assistant, text: "done"), stopReason: .end_turn)
        let route = AgentModelRoute(
            purpose: invocation.selection.purpose,
            profile: AgentModelProfile(
                identifier: "fixture.budget.profile",
                gatewayIdentifier: "fixture.budget.gateway",
                model: "fixture",
                purposes: [invocation.selection.purpose],
                capabilities: [.text, .reasoning]
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
            let task = Task {
                do {
                    continuation.yield(.completed(try await buffered(invocation)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension AgenticProgramRuntimeFlowTesting {
    /// Compaction rewrites what stays of the cached prefix once; each later
    /// request reads the saved tokens fewer. At a 1.25× write and 0.1× read
    /// price, 30k tokens of which 6k are compacted take 46 requests to repay;
    /// where writes cost the plain input price, fewer.
    static func runCompactionPayback() async throws -> [TestDiagnostic] {
        try Expect.equal(
            ContextWindow.compactionPayback(prefix: 30_000, saving: 6_000, read: 0.30, write: 3.75),
            46,
            "24k rewritten at 3.45 extra, repaid at 6k × 0.30 per request"
        )
        try Expect.equal(
            ContextWindow.compactionPayback(prefix: 30_000, saving: 6_000, read: 1.25, write: 2.50),
            4,
            "with a plain input price as the write price"
        )
        try Expect.equal(
            ContextWindow.compactionPayback(prefix: 10_000, saving: 9_000, read: 1, write: 1),
            1,
            "free rewrites repay at once"
        )
        return []
    }
}
