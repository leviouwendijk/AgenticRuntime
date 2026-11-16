import Agentic
import AgenticContext
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    /// What a dynamic request leaves out of the transcript is a run event
    /// naming each decision; nothing leaves the model's view unreported.
    static func runContextChangeEvent() async throws -> [TestDiagnostic] {
        let model = ContextChangeModel()
        let executor = AgentExecutor(
            model: .init(invoker: model),
            configuration: .init(
                contextMode: .dynamic,
                contextPolicy: .init(
                    preferredInputTokens: 1_000,
                    maximumInputTokens: 20_000,
                    reservedOutputTokens: 200,
                    history: .init(maximumTurns: 4, maximumTokens: 1_500, elideResultsOver: 128)
                )
            ),
            capabilityState: AgentCapabilityState(installed: .none)
        )
        let call = FunctionCall(id: "read.1", name: "read_file", input: .null)
        let result = try await executor.run(
            AgentRequest(messages: [
                Message(id: "ask", role: .user, content: .init(text: "Read the file.")),
                Message(id: "call", role: .assistant, content: .init(blocks: [.call(call)])),
                Message(id: "result", role: .tool, content: .init(blocks: [.result(.init(
                    call: call.reference,
                    output: .string(String(repeating: "source line\n", count: 1_500))
                ))])),
                Message(id: "answer", role: .assistant, content: .init(text: "Findings: A, B, C.")),
                Message(id: "followup", role: .user, content: .init(text: "Implement A, B and C.")),
            ]),
            sessionID: "context-change-run"
        )

        let changed = result.events.filter { $0.kind == .context_changed }
        try Expect.equal(changed.count, 1, "one event for the request's decisions")
        let changes = changed.first?.contextChanges ?? []
        try Expect.true(
            changes.contains { $0.messageID == "result" && $0.call?.id == "read.1" },
            "the shortened result is named with its call: \(changes)"
        )
        let sent = await model.lastRequest()?.messages.map(\.id) ?? []
        try Expect.true(
            sent.contains("answer") && sent.contains("followup"),
            "the answer the follow-up refers to is sent: \(sent)"
        )
        return [.field("context_changed", changed.first?.summary ?? "")]
    }
}

private actor ContextChangeModel: AgentModelInvoking {
    private var requests: [AgentRequest] = []

    func lastRequest() -> AgentRequest? { requests.last }

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocation.Result {
        requests.append(invocation.request)
        let profile = AgentModelProfile(
            identifier: "fixture.context",
            gatewayIdentifier: "fixture.context",
            model: "fixture",
            purposes: [invocation.selection.purpose]
        )
        return .init(
            response: AgentResponse(
                message: Message(role: .assistant, text: "done"),
                stopReason: .end_turn
            ),
            route: .init(
                route: .init(purpose: invocation.selection.purpose, profile: profile),
                diagnostics: [],
                requestMetadata: invocation.request.metadata,
                responseMetadata: [:],
                usage: nil
            )
        )
    }

    nonisolated func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<AgentModelInvocation.Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.completed(try await self.buffered(invocation)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
