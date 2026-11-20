import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    /// Steering joins a run at its next model request. A message that
    /// arrives while the model gives its final answer is not stranded: the
    /// run takes one more turn for it.
    static func runSteering() async throws -> [TestDiagnostic] {
        let model = SteeringModel()
        let executor = AgentExecutor(
            model: .init(invoker: model),
            capabilityState: AgentCapabilityState(installed: .none)
        )
        let run = Task {
            try await executor.run(
                AgentRequest(messages: [Message(role: .user, text: "start")]),
                sessionID: "steering-run"
            )
        }
        await model.firstCallArrived()
        await executor.steer(Message(role: .user, text: "also check the tests"))
        await model.releaseFirstCall()
        let result = try await run.value

        let calls = await model.calls()
        try Expect.equal(calls.count, 2, "the run took one more turn for the steering")
        try Expect.equal(
            calls[1].request.messages.last?.content.text,
            "also check the tests",
            "the steering is the newest message of the next request"
        )
        try Expect.equal(result.response?.message.content.text, "answer 2", "the run completes after it")
        try Expect.true(
            result.events.contains { $0.kind == .input_applied },
            "the steering is recorded as applied"
        )
        try Expect.true(await !executor.runControl.hasSteering, "nothing is left over")
        return []
    }
}

private actor SteeringModel: AgentModelInvoking {
    private var invocations: [AgentModelInvocation] = []
    private var held: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var arrived = false

    func calls() -> [AgentModelInvocation] { invocations }

    func firstCallArrived() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func releaseFirstCall() {
        held?.resume()
        held = nil
    }

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocation.Result {
        invocations.append(invocation)
        let number = invocations.count
        if number == 1 {
            arrived = true
            arrival?.resume()
            arrival = nil
            await withCheckedContinuation { held = $0 }
        }
        let response = AgentResponse(
            message: Message(role: .assistant, text: "answer \(number)"),
            stopReason: .end_turn
        )
        let profile = AgentModelProfile(
            identifier: "fixture.steering",
            gatewayIdentifier: "fixture.steering",
            model: "fixture",
            purposes: [invocation.selection.purpose]
        )
        return .init(
            response: response,
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
