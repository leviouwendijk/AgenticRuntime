import Agentic
import AgenticRuntime
import AgenticStandard
import Foundation
import IO
import Primitives
import Schema
import TestFlows

/// A large result reaches the model as its beginning plus where
/// `read_result` continues; the log keeps it whole and `read_result` pages
/// through it.
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
        let state = BudgetModelState()
        let registry = try ToolRegistry {
            BudgetListingTool()
            Standard.Tools.ReadResult()
        }
        let tools = [BudgetListingTool.definition.identifier, Standard.Tools.ReadResult.identifier]
        let executor = AgentExecutor(
            model: .init(invoker: BudgetModelInvoker(state: state, calls: [listing, page])),
            configuration: .init(
                runLimits: .init(iterations: 4),
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
        try Expect.equal(invocations.count, 3, "List, page, answer")

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
            invocations[1].request.tools.contains { $0.name == Standard.Tools.ReadResult.identifier.rawValue },
            "read_result is revealed when a result is shortened"
        )
        try Expect.true(
            !invocations[0].request.tools.contains { $0.name == Standard.Tools.ReadResult.identifier.rawValue },
            "and not before"
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
        return [.field("shown_characters", "\(shown.modelText.count) of \(full.count)")]
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
