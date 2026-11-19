import Agentic
import AgenticRuntime
import AgenticStandard
import Macros
import Primitives
import Schema
import TestFlows

@JSONSchema
private struct RevealEchoValue: Sendable, Codable, Hashable {
    let value: String
}

private struct RevealEchoTool: Tool {
    typealias Input = RevealEchoValue
    typealias Output = RevealEchoValue

    static let definition = ToolDefinition(
        identifier: "fixture.reveal.echo",
        purpose: "Echoes a value.",
        risk: .observe
    )

    func call(_ input: Input, in _: ToolContext) async throws -> Output {
        input
    }
}

private actor RevealRequests {
    var requests: [AgentRequest] = []
    func record(_ request: AgentRequest) -> Int {
        requests.append(request)
        return requests.count - 1
    }
}

/// Answers each request with the next scripted call, then ends the turn.
private struct RevealInvoker: AgentModelInvoking {
    let requests: RevealRequests
    let calls: [FunctionCall]

    func buffered(_ invocation: AgentModelInvocation) async throws -> AgentModelInvocation.Result {
        let index = await requests.record(invocation.request)
        let response = index < calls.count
            ? AgentResponse(
                message: Message(role: .assistant, content: .init(blocks: [.call(calls[index])])),
                stopReason: .tool_use
            )
            : AgentResponse(message: Message(role: .assistant, text: "done"), stopReason: .end_turn)
        let route = AgentModelRoute(
            purpose: invocation.selection.purpose,
            profile: AgentModelProfile(
                identifier: "fixture.reveal.profile",
                gatewayIdentifier: "fixture.reveal.gateway",
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
                    continuation.yield(.completed(try await buffered(invocation)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

extension AgenticProgramRuntimeFlowTesting {
    /// A capability revealed mid-session is declared while the prompt is
    /// small (one cache rewrite) and called through `call_capability` above
    /// the policy's threshold (the definitions, and the cache, hold).
    static func runRevealDecision() async throws -> [TestDiagnostic] {
        let echo = RevealEchoTool.definition.identifier
        func arguments(_ value: some Encodable) throws -> JSONValue {
            .object(["arguments": try JSONValue.encoding(value)])
        }
        let inspect = FunctionCall(
            id: "c-inspect",
            name: Standard.Tools.InspectCapability.identifier.rawValue,
            input: try arguments(Standard.Tools.InspectCapability.Input(kind: .tool, identifier: echo.rawValue))
        )

        func run(
            threshold: Int?,
            then call: FunctionCall
        ) async throws -> (tools: [[String]], result: AgentExecutor.Result) {
            let requests = RevealRequests()
            let tools = AgentCapabilitySet(tools: [echo] + Standard.Tools.discovery)
            let executor = AgentExecutor(
                model: .init(invoker: RevealInvoker(requests: requests, calls: [inspect, call])),
                configuration: .init(
                    runLimits: .init(iterations: 4),
                    contextPolicy: .init(deferRevealsAbove: threshold)
                ),
                tooling: .init(registry: try ToolRegistry {
                    RevealEchoTool()
                    Standard.Tools.ListCapabilities()
                    Standard.Tools.SearchCapabilities()
                    Standard.Tools.InspectCapability()
                    Standard.Tools.CallCapability()
                }),
                capabilityState: AgentCapabilityState(installed: tools, available: tools, visible: AgentCapabilitySet.none)
            )
            let result = try await executor.run(
                AgentRequest(messages: [Message(role: .user, text: "Echo hi.")]),
                sessionID: "reveal-\(threshold.map(String.init) ?? "none")"
            )
            return (await requests.requests.map { $0.tools.map(\.name) }, result)
        }
        func response(_ id: String, in result: AgentExecutor.Result) -> FunctionCall.Response? {
            result.state.messages.flatMap(\.content.blocks).lazy.compactMap { block -> FunctionCall.Response? in
                guard case .result(let response) = block, response.call.id == id else { return nil }
                return response
            }.first
        }

        // Small prompt: declared, the definitions grow once, called by name.
        let direct = FunctionCall(id: "c-echo", name: echo.rawValue, input: try arguments(RevealEchoValue(value: "hi")))
        let declared = try await run(threshold: 16_000, then: direct)
        try Expect.equal(declared.tools.count, 3, "inspect, echo, answer")
        try Expect.equal(declared.tools[1], declared.tools[0] + [echo.rawValue], "declared: appended to the definitions")
        let declaredEcho = try Expect.notNil(response("c-echo", in: declared.result), "the echo ran")
        try Expect.false(declaredEcho.isError, "called by its own name")
        let decision = try Expect.notNil(
            declared.result.events.compactMap { $0.advertisement?.revealDecision }.first,
            "the decision is recorded"
        )
        try Expect.false(decision.deferred, "under the threshold it is declared")

        // Over the threshold: deferred, the definitions hold, called through
        // call_capability and run as the echo itself.
        let dispatched = FunctionCall(
            id: "c-dispatch",
            name: Standard.Tools.CallCapability.identifier.rawValue,
            input: try arguments(Standard.Tools.CallCapability.Input(
                identifier: echo.rawValue,
                input: .object(["value": .string("hi")])
            ))
        )
        let deferred = try await run(threshold: 0, then: dispatched)
        try Expect.equal(deferred.tools.count, 3, "inspect, dispatch, answer")
        try Expect.equal(deferred.tools[1], deferred.tools[0], "deferred: the definitions do not change")
        try Expect.equal(deferred.tools[2], deferred.tools[0], "not after the call either")
        try Expect.false(deferred.tools[1].contains(echo.rawValue), "the echo is not declared")
        let inspected = try Expect.notNil(response("c-inspect", in: deferred.result), "the contract was returned")
        try Expect.true(inspected.modelText.contains("call_capability"), "and says to call it through the dispatcher")
        let dispatchedEcho = try Expect.notNil(response("c-dispatch", in: deferred.result), "the dispatch was answered")
        try Expect.false(dispatchedEcho.isError, "it ran as the echo: \(dispatchedEcho.modelText)")
        try Expect.true(dispatchedEcho.modelText.contains("hi"), "with the echo's output")
        let advertisement = try Expect.notNil(
            deferred.result.events.last { $0.kind == .schemas_advertised }?.advertisement,
            "the advertisement is recorded"
        )
        try Expect.equal(advertisement.deferred, [echo.rawValue], "naming what is deferred")
        try Expect.false(advertisement.rewritesCachedPrefix, "without a rewrite")

        // A dispatch naming nothing callable is answered by the dispatcher.
        let unknown = FunctionCall(
            id: "c-unknown",
            name: Standard.Tools.CallCapability.identifier.rawValue,
            input: try arguments(Standard.Tools.CallCapability.Input(identifier: "fixture.nothing", input: .object([:])))
        )
        let refused = try await run(threshold: 0, then: unknown)
        let refusal = try Expect.notNil(response("c-unknown", in: refused.result), "the dispatch was answered")
        try Expect.true(refusal.isError && refusal.modelText.contains("inspect_capability"), "with how to find it: \(refusal.modelText)")
        return []
    }
}
