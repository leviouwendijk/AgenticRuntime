import Agentic
import AgenticRuntime
import AgenticStandard
import Macros
import Primitives
import Schema
import TestFlows

@JSONSchema
private struct UndeclaredEchoValue: Sendable, Codable, Hashable {
    let value: String
}

private struct UndeclaredEchoTool: Tool {
    typealias Input = UndeclaredEchoValue
    typealias Output = UndeclaredEchoValue

    static let definition = ToolDefinition(
        identifier: "fixture.undeclared.echo",
        purpose: "Echoes a value.",
        risk: .observe
    )

    func call(_ input: Input, in _: ToolContext) async throws -> Output {
        input
    }
}

private actor UndeclaredRequests {
    var requests: [AgentRequest] = []
    func record(_ request: AgentRequest) -> Int {
        requests.append(request)
        return requests.count - 1
    }
}

/// Answers each request with the next scripted call, then ends the turn.
private struct UndeclaredInvoker: AgentModelInvoking {
    let requests: UndeclaredRequests
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
                identifier: "fixture.undeclared.profile",
                gatewayIdentifier: "fixture.undeclared.gateway",
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
    /// Every available capability is callable, declared or not, and the
    /// tool definitions stay as the conversation fixed them: inspection
    /// changes nothing, operator changes wait as pending until a refresh,
    /// and a declared capability that is withdrawn stays declared but is
    /// refused.
    static func runUndeclaredCapabilities() async throws -> [TestDiagnostic] {
        let echo = UndeclaredEchoTool.definition.identifier
        let echoReference = CapabilityReference.tool(echo)
        func arguments(_ value: some Encodable) throws -> JSONValue {
            .object(["arguments": try JSONValue.encoding(value)])
        }
        let inspect = FunctionCall(
            id: "c-inspect",
            name: Standard.Tools.InspectCapability.identifier.rawValue,
            input: try arguments(Standard.Tools.InspectCapability.Input(kind: .tool, identifier: echo.rawValue))
        )

        struct Outcome {
            let tools: [[String]]
            let result: AgentExecutor.Result
            let visible: AgentCapabilitySet
        }
        func run(
            _ calls: [FunctionCall],
            visible: AgentCapabilitySet = .none,
            available: AgentCapabilitySet? = nil,
            declared: [CapabilityReference]? = nil,
            session: String
        ) async throws -> Outcome {
            let requests = UndeclaredRequests()
            let installed = AgentCapabilitySet(tools: [echo] + Standard.Tools.discovery)
            let state = AgentCapabilityState(
                installed: installed,
                available: available ?? installed,
                visible: visible
            )
            let executor = AgentExecutor(
                model: .init(invoker: UndeclaredInvoker(requests: requests, calls: calls)),
                configuration: .init(
                    runLimits: .init(iterations: 4),
                    declared: declared
                ),
                tooling: .init(registry: try ToolRegistry {
                    UndeclaredEchoTool()
                    Standard.Tools.ListCapabilities()
                    Standard.Tools.SearchCapabilities()
                    Standard.Tools.InspectCapability()
                    Standard.Tools.CallCapability()
                }),
                capabilityState: state
            )
            let result = try await executor.run(
                AgentRequest(messages: [Message(role: .user, text: "Echo hi.")]),
                sessionID: "undeclared-\(session)"
            )
            return Outcome(
                tools: await requests.requests.map { $0.tools.map(\.name) },
                result: result,
                visible: await state.snapshot().visible
            )
        }
        func response(_ id: String, in result: AgentExecutor.Result) -> FunctionCall.Response? {
            result.state.messages.flatMap(\.content.blocks).lazy.compactMap { block -> FunctionCall.Response? in
                guard case .result(let response) = block, response.call.id == id else { return nil }
                return response
            }.first
        }
        func lastAdvertisement(_ result: AgentExecutor.Result) throws -> Run.Event.Advertisement {
            try Expect.notNil(
                result.events.last { $0.kind == .schemas_advertised }?.advertisement,
                "the run advertised"
            )
        }

        // Inspection reads; it neither reveals nor changes the definitions.
        // The echo is then called by its own name, without a definition.
        let direct = FunctionCall(id: "c-echo", name: echo.rawValue, input: try arguments(UndeclaredEchoValue(value: "hi")))
        let byName = try await run([inspect, direct], session: "by-name")
        try Expect.equal(byName.tools.count, 3, "inspect, echo, answer")
        try Expect.true(byName.tools.allSatisfy { $0 == byName.tools[0] }, "the definitions never change")
        try Expect.false(byName.tools[0].contains(echo.rawValue), "the echo is not declared")
        try Expect.false(byName.visible.tools.contains(echo), "inspection reveals nothing")
        let inspected = try Expect.notNil(response("c-inspect", in: byName.result), "the contract was returned")
        try Expect.true(inspected.modelText.contains("call_capability"), "and says to call it through the dispatcher")
        try Expect.false(
            byName.result.events.contains { ($0.capabilityChanges ?? []).contains { $0.source == .tool_reveal } },
            "no reveal is recorded"
        )
        let byNameEcho = try Expect.notNil(response("c-echo", in: byName.result), "the echo was answered")
        try Expect.false(byNameEcho.isError, "called by its own name: \(byNameEcho.modelText)")
        let opening = try lastAdvertisement(byName.result)
        try Expect.true(opening.callable >= 1, "the echo is counted as callable")
        try Expect.false(opening.rewritesCachedPrefix, "without a rewrite")

        // Through the dispatcher it runs as the echo itself.
        let dispatched = FunctionCall(
            id: "c-dispatch",
            name: Standard.Tools.CallCapability.identifier.rawValue,
            input: try arguments(Standard.Tools.CallCapability.Input(
                identifier: echo.rawValue,
                input: .object(["value": .string("hi")])
            ))
        )
        let throughDispatcher = try await run([inspect, dispatched], session: "dispatched")
        try Expect.true(throughDispatcher.tools.allSatisfy { $0 == throughDispatcher.tools[0] }, "the definitions never change")
        let dispatchedEcho = try Expect.notNil(response("c-dispatch", in: throughDispatcher.result), "the dispatch was answered")
        try Expect.false(dispatchedEcho.isError, "it ran as the echo: \(dispatchedEcho.modelText)")
        try Expect.true(dispatchedEcho.modelText.contains("hi"), "with the echo's output")
        try Expect.false(dispatchedEcho.modelText.contains("among your tools"), "an undeclared dispatch gets no note")

        // A declared tool called through the dispatcher still runs, and its
        // result says to call it by name.
        let wrapped = try await run([dispatched], visible: AgentCapabilitySet(tools: [echo]), session: "wrapped")
        let wrappedEcho = try Expect.notNil(response("c-dispatch", in: wrapped.result), "the wrapped call was answered")
        try Expect.false(wrappedEcho.isError, "it ran as the echo: \(wrappedEcho.modelText)")
        try Expect.true(
            wrappedEcho.modelText.contains("hi") && wrappedEcho.modelText.contains("is among your tools: call it by its own name"),
            "with the echo's output and the pushback: \(wrappedEcho.modelText)"
        )

        // A dispatch naming nothing callable is answered by the dispatcher.
        let unknown = FunctionCall(
            id: "c-unknown",
            name: Standard.Tools.CallCapability.identifier.rawValue,
            input: try arguments(Standard.Tools.CallCapability.Input(identifier: "fixture.nothing", input: .object([:])))
        )
        let refused = try await run([unknown], session: "unknown")
        let refusal = try Expect.notNil(response("c-unknown", in: refused.result), "the dispatch was answered")
        try Expect.true(refusal.isError && refusal.modelText.contains("inspect_capability"), "with how to find it: \(refusal.modelText)")

        // A later turn after the operator selected the echo: the definitions
        // stay as the earlier run declared them, and the echo is pending.
        let earlier = opening.entries.compactMap(\.reference)
        try Expect.equal(earlier.count, opening.entries.count, "the advertisement names each declared capability")
        let selected = AgentCapabilitySet(tools: [echo])
        let kept = try await run([], visible: selected, declared: earlier, session: "kept")
        try Expect.equal(kept.tools.first, byName.tools.first, "the definitions hold across the turn")
        let pending = try lastAdvertisement(kept.result).pending
        try Expect.equal(pending?.added, [echo.rawValue], "the selection waits as pending")

        // A refresh (the host passes nil) declares the selection.
        let refreshed = try await run([], visible: selected, session: "refreshed")
        try Expect.true(refreshed.tools.first?.contains(echo.rawValue) == true, "refreshed: the echo is declared")
        try Expect.true(try lastAdvertisement(refreshed.result).pending == nil, "nothing left pending")

        // Input that does not fit an undeclared capability is answered with
        // its contract; a name nothing answers to, with how to find one.
        let misfit = FunctionCall(
            id: "c-misfit",
            name: echo.rawValue,
            input: .object(["arguments": .object(["wrong": .string("hi")])])
        )
        let nowhere = FunctionCall(
            id: "c-nowhere",
            name: "fixture.nowhere",
            input: .object(["arguments": .object([:])])
        )
        let taught = try await run([misfit, nowhere], session: "taught")
        let misfitAnswer = try Expect.notNil(response("c-misfit", in: taught.result), "the misfit was answered")
        try Expect.true(
            misfitAnswer.isError && misfitAnswer.modelText.contains("Its input") && misfitAnswer.modelText.contains("properties"),
            "with the echo's contract: \(misfitAnswer.modelText)"
        )
        let nowhereAnswer = try Expect.notNil(response("c-nowhere", in: taught.result), "the unknown name was answered")
        try Expect.true(
            nowhereAnswer.isError && nowhereAnswer.modelText.contains("search_capabilities"),
            "with how to find a capability: \(nowhereAnswer.modelText)"
        )
        // A declared tool's misfit gets no contract: its definition has it.
        let declaredMisfit = try await run([misfit], visible: AgentCapabilitySet(tools: [echo]), session: "declared-misfit")
        let declaredAnswer = try Expect.notNil(response("c-misfit", in: declaredMisfit.result), "the misfit was answered")
        try Expect.true(
            declaredAnswer.isError && !declaredAnswer.modelText.contains("Its input"),
            "without the contract: \(declaredAnswer.modelText)"
        )

        // A dispatched call is shown as the capability it names.
        try Expect.equal(dispatched.dispatchedIdentifier, echo.rawValue, "the dispatch names the echo")
        try Expect.true(direct.dispatchedIdentifier == nil, "a direct call is not a dispatch")
        try Expect.equal(
            throughDispatcher.result.state.messages.dispatchedCallIDs,
            ["c-dispatch"],
            "the dispatched call is found in the transcript"
        )

        // Withdrawn: still declared, so the definitions hold, but refused.
        let withdrawnCall = FunctionCall(id: "c-withdrawn", name: echo.rawValue, input: try arguments(UndeclaredEchoValue(value: "hi")))
        let withdrawn = try await run(
            [withdrawnCall],
            available: AgentCapabilitySet(tools: Standard.Tools.discovery),
            declared: earlier + [echoReference],
            session: "withdrawn"
        )
        try Expect.true(withdrawn.tools.first?.contains(echo.rawValue) == true, "the withdrawn echo stays declared")
        try Expect.equal(lastAdvertisement(withdrawn.result).pending?.removed, [echo.rawValue], "its removal is pending")
        let withdrawnEcho = try Expect.notNil(response("c-withdrawn", in: withdrawn.result), "the call was answered")
        try Expect.true(withdrawnEcho.isError, "and refused: \(withdrawnEcho.modelText)")
        return []
    }
}
