import Agentic
import AgenticIntents
@_spi(Testing) import AgenticRuntime
import Foundation
import IO
import Primitives
import Schema
import TestFlows

/// An unattended run stores a call that needs review as an intent and goes
/// on; the approved intent later runs the prepared plan once. Without an
/// intent store the same call suspends, as a pending approval.
extension AgenticProgramRuntimeFlowTesting {
    static func runDeferredCall() async throws -> [TestDiagnostic] {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deferral-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileSystem.default.remove(root) }

        let probe = DeferralProbe()
        let registry = try ToolRegistry { DeferralFixtureTool(probe: probe) }
        let manager = Intents.Manager(store: Intents.FileStore(directory: root))
        let state = DeferralModelState()

        let result = try await deferralExecutor(
            registry: registry,
            state: state,
            services: try ToolServices().inserting(manager)
        ).run(
            AgentRequest(messages: [Message(role: .user, text: "Write it.")]),
            sessionID: "deferral"
        )

        try Expect.equal(result.phase, .completed, "The run goes on past the deferred call")
        try Expect.true(result.pendingApproval == nil, "Nothing waits for a person")
        try Expect.equal(
            result.toolUses.map(\.disposition),
            [.deferred_for_review],
            "The call is recorded as deferred"
        )
        try Expect.true(
            result.events.contains { $0.kind == .tool_deferred },
            "The run log says it was deferred"
        )
        try Expect.equal(await probe.values(), [], "Deferring runs nothing")

        let intents = try await manager.list(sessionID: "deferral")
        let intent = try Expect.notNil(intents.first, "The call is stored as an intent")
        try Expect.equal(intents.count, 1, "Once")
        try Expect.equal(intent.status, .pending, "Waiting for review")

        let invocations = await state.snapshot()
        let shown = invocations.last?.request.messages.flatMap(\.content.blocks).lazy.compactMap { block -> FunctionCall.Response? in
            guard case .result(let response) = block else { return nil }
            return response
        }.first
        let response = try Expect.notNil(shown, "The model hears about the deferral")
        try Expect.equal(response.isError, false, "as a result, not an error")
        try Expect.equal(
            try response.output.value(forDotPath: "intent").stringValue,
            intent.id.raw,
            "naming the intent"
        )

        _ = try await manager.review(intent.id, decision: .approve, reviewer: "owner")
        let executed = try await Intents.Executor(
            manager: manager,
            tools: ToolExecutor(registry: registry, policy: .init(autonomyMode: .auto_observe))
        ).execute(intent.id, in: ToolContext())

        try Expect.equal(executed.status, .executed, "The approved intent runs")
        try Expect.equal(await probe.values(), ["notes"], "exactly the prepared plan, once")

        return [.field("intent", intent.id.raw)]
    }

    static func runDeferralFallback() async throws -> [TestDiagnostic] {
        let probe = DeferralProbe()
        let result = try await deferralExecutor(
            registry: try ToolRegistry { DeferralFixtureTool(probe: probe) },
            state: DeferralModelState(),
            services: ToolServices()
        ).run(
            AgentRequest(messages: [Message(role: .user, text: "Write it.")]),
            sessionID: "deferral-fallback"
        )

        try Expect.true(result.pendingApproval != nil, "Without an intent store the call waits for a person")
        try Expect.equal(
            result.toolUses.map(\.disposition),
            [.suspended_for_approval],
            "as a suspended approval"
        )
        try Expect.true(
            result.events.contains { $0.kind == .pending_approval && $0.summary.contains("not deferred") },
            "and the run log says why it was not deferred"
        )
        try Expect.equal(await probe.values(), [], "Nothing ran")
        return []
    }
}

private func deferralExecutor(
    registry: ToolRegistry,
    state: DeferralModelState,
    services: ToolServices
) -> AgentExecutor {
    let tools = [DeferralFixtureTool.definition.identifier]
    return AgentExecutor(
        model: .init(invoker: DeferralModelInvoker(state: state)),
        configuration: .init(
            runLimits: .init(iterations: 4),
            autonomyMode: .auto_observe
        ),
        tooling: .init(
            registry: registry,
            approvalHandler: Intents.DeferringApprovalHandler(),
            services: services
        ),
        capabilityState: AgentCapabilityState(
            installed: .init(tools: tools),
            available: .init(tools: tools),
            visible: .init(tools: tools)
        )
    )
}

private actor DeferralProbe {
    private var written: [String] = []

    func write(_ value: String) {
        written.append(value)
    }

    func values() -> [String] {
        written
    }
}

private struct DeferralInput: Sendable, Codable, Hashable, JSONSchemaProviding {
    let name: String

    static var jsonschema: JSONSchema {
        JSONSchema.object {
            JSONSchema.string("name", required: true)
        }
    }
}

private struct DeferralOutput: Sendable, Codable, Hashable, JSONSchemaProviding {
    let written: String

    static var jsonschema: JSONSchema {
        JSONSchema.object {
            JSONSchema.string("written", required: true)
        }
    }
}

private enum DeferralOperation: AgentPreparedOperation {
    struct Plan: Sendable, Codable, Hashable {
        let name: String
    }

    static let schema = PreparedOperation.Schema(
        identifier: "fixture.deferral_write",
        version: .init(major: 1, minor: 0, patch: 0)
    )
}

/// A bounded mutation that needs review under `auto_observe` and only
/// executes its prepared plan.
private struct DeferralFixtureTool: Tool {
    typealias Input = DeferralInput
    typealias Output = DeferralOutput

    static let definition = ToolDefinition(
        identifier: "fixture_deferral_write",
        purpose: "Prepared write fixture.",
        risk: .boundedmutate
    )

    let probe: DeferralProbe

    func prepare(
        _ input: Input,
        in _: ToolContext
    ) async throws -> CapabilityPreparation<ToolPreflight> {
        .init(
            review: .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Write \(input.name)"
            ),
            operation: try DeferralOperation.envelope(.init(name: input.name))
        )
    }

    func call(
        _: Input,
        in _: ToolContext
    ) async throws -> Output {
        throw ToolPreparationError.prepared_operation_required
    }

    func call(
        _: Input,
        prepared operation: PreparedOperation.Envelope?,
        in _: ToolContext
    ) async throws -> Output {
        guard let operation else {
            throw ToolPreparationError.prepared_operation_required
        }
        let plan = try DeferralOperation.plan(from: operation)
        await probe.write(plan.name)
        return .init(written: plan.name)
    }
}

private actor DeferralModelState {
    private var invocations: [AgentModelInvocation] = []

    func record(_ invocation: AgentModelInvocation) -> Int {
        invocations.append(invocation)
        return invocations.count - 1
    }

    func snapshot() -> [AgentModelInvocation] {
        invocations
    }
}

/// Calls the fixture once, then answers.
private struct DeferralModelInvoker: AgentModelInvoking {
    let state: DeferralModelState

    func buffered(_ invocation: AgentModelInvocation) async throws -> AgentModelInvocation.Result {
        let index = await state.record(invocation)
        let call = FunctionCall(
            id: "c-write",
            name: DeferralFixtureTool.definition.identifier.rawValue,
            input: .object(["arguments": .object(["name": .string("notes")])])
        )
        let response = index == 0
            ? AgentResponse(
                message: Message(role: .assistant, content: .init(blocks: [.call(call)])),
                stopReason: .tool_use
            )
            : AgentResponse(message: Message(role: .assistant, text: "done"), stopReason: .end_turn)
        let route = AgentModelRoute(
            purpose: invocation.selection.purpose,
            profile: AgentModelProfile(
                identifier: "fixture.deferral.profile",
                gatewayIdentifier: "fixture.deferral.gateway",
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
