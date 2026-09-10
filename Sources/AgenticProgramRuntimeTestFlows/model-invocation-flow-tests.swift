import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runModelInvocationTransport()
        async throws
        -> [TestFlowDiagnostic]
    {
        let recorder = FixtureModelInvocationRecorder()
        let invoker = FixtureModelInvoker(
            recorder: recorder
        )
        let selection = AgentModelSelection(
            purpose: .reviewer,
            requirements: .init(
                capabilities: [
                    .text,
                    .reasoning,
                ]
            ),
            metadata: [
                "fixture_selection": "transport",
            ]
        )
        let request = AgentRequest(
            messages: [
                AgentMessage(
                    role: .user,
                    text: "exercise invocation transport"
                ),
            ],
            metadata: [
                "fixture_request": "transport",
            ]
        )
        let runner = AgentRunner(
            model: .init(
                invoker: invoker,
                selection: selection
            )
        )
        let result = try await runner.run(
            request,
            sessionID: "fixture-model-invocation-buffered"
        )
        let invocations = await recorder.snapshot()

        try Expect.equal(
            invocations.count,
            1,
            "buffered Runtime execution performs exactly one semantic model invocation"
        )

        let invocation = invocations[0]

        try Expect.equal(
            invocation.request,
            request,
            "Runtime transports the prepared semantic request through AgentModelInvocation"
        )
        try Expect.equal(
            invocation.selection,
            selection,
            "Runtime transports the runner model selection through AgentModelInvocation"
        )
        try Expect.equal(
            invocation.context.toolCallResolver != nil,
            true,
            "Runtime supplies the governed model tool-call resolver through invocation context"
        )
        try Expect.equal(
            result.response?.message.content.text,
            "fixture-response",
            "Runtime consumes the AgentModelInvocationResult response"
        )

        return [
            .field(
                "invocations",
                String(invocations.count)
            ),
            .field(
                "purpose",
                invocation.selection.purpose.rawValue
            ),
            .field(
                "context_tool_resolver",
                String(invocation.context.toolCallResolver != nil)
            ),
        ]
    }

    static func runModelInvocationStreamingCompletion()
        async throws
        -> [TestFlowDiagnostic]
    {
        let recorder = FixtureModelInvocationRecorder()
        let invoker = FixtureModelInvoker(
            recorder: recorder
        )
        let selection = AgentModelSelection.reviewer
        let request = AgentRequest(
            messages: [
                AgentMessage(
                    role: .user,
                    text: "exercise streaming completion"
                ),
            ]
        )
        var configuration = AgentRunnerConfiguration.default
        configuration.responseDelivery = .stream

        let runner = AgentRunner(
            model: .init(
                invoker: invoker,
                selection: selection
            ),
            configuration: configuration
        )
        let result = try await runner.run(
            request,
            sessionID: "fixture-model-invocation-stream"
        )
        let invocations = await recorder.snapshot()
        let completedEvents = result.events.filter { event in
            event.kind == .model_stream_completed
        }

        try Expect.equal(
            invocations.count,
            1,
            "streaming Runtime execution performs exactly one semantic model invocation"
        )
        try Expect.equal(
            completedEvents.count,
            1,
            "one invocation-level completion becomes exactly one Runtime stream completion"
        )
        try Expect.equal(
            result.response?.message.content.text,
            "fixture-response",
            "streaming Runtime finalizes from the invocation-level completion result"
        )

        return [
            .field(
                "invocations",
                String(invocations.count)
            ),
            .field(
                "stream_completions",
                String(completedEvents.count)
            ),
            .field(
                "response",
                result.response?.message.content.text ?? "<none>"
            ),
        ]
    }

    static func runModeModelSelectionPropagation()
        async throws
        -> [TestFlowDiagnostic]
    {
        let expectedSelection = AgentModelSelection.reviewer
        let mode = AgenticMode(
            id: "fixture-review-mode",
            title: "Fixture review",
            routeDefaults: .init(
                primaryPurpose: .reviewer,
                selections: [
                    .reviewer: expectedSelection,
                ]
            ),
            autonomyMode: .auto_observe
        )
        let application = try ModeRuntimeApplication(
            selection: ModeSelection(
                mode: mode
            ),
            tools: .init()
        )
        let recorder = FixtureModelInvocationRecorder()
        let invoker = FixtureModelInvoker(
            recorder: recorder
        )
        let runner = AgentRunner(
            model: .init(
                invoker: invoker
            ),
            modeApplication: application
        )
        let request = AgentRequest(
            messages: [
                AgentMessage(
                    role: .user,
                    text: "exercise mode model selection"
                ),
            ]
        )

        _ = try await runner.run(
            request,
            sessionID: "fixture-mode-model-selection"
        )

        let invocations = await recorder.snapshot()

        try Expect.equal(
            application.modelSelection,
            expectedSelection,
            "ModeRuntimeApplication resolves the mode primary selection"
        )
        try Expect.equal(
            invocations.count,
            1,
            "mode-backed runner performs one model invocation"
        )
        try Expect.equal(
            invocations[0].selection,
            expectedSelection,
            "mode application model selection reaches the actual AgentModelInvocation"
        )

        return [
            .field(
                "mode",
                application.modeID.rawValue
            ),
            .field(
                "purpose",
                invocations[0].selection.purpose.rawValue
            ),
        ]
    }
}

private actor FixtureModelInvocationRecorder {
    private var invocations: [AgentModelInvocation] = []

    func append(
        _ invocation: AgentModelInvocation
    ) {
        invocations.append(
            invocation
        )
    }

    func snapshot() -> [AgentModelInvocation] {
        invocations
    }
}

private struct FixtureModelInvoker: AgentModelInvoking {
    let recorder: FixtureModelInvocationRecorder

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocationResult {
        await recorder.append(
            invocation
        )

        return fixtureInvocationResult(
            for: invocation
        )
    }

    func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<AgentModelInvocationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await recorder.append(
                    invocation
                )

                let routeResult = fixtureRouteResult(
                    for: invocation.selection
                )

                continuation.yield(
                    .routed(routeResult)
                )
                continuation.yield(
                    .completed(
                        fixtureInvocationResult(
                            for: invocation,
                            routeResult: routeResult
                        )
                    )
                )
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private func fixtureInvocationResult(
    for invocation: AgentModelInvocation,
    routeResult: AgentModelRouteResult? = nil
) -> AgentModelInvocationResult {
    let response = AgentResponse(
        message: AgentMessage(
            role: .assistant,
            text: "fixture-response"
        ),
        stopReason: .end_turn,
        metadata: [
            "fixture_response": "completed",
        ]
    )
    let routeResult = routeResult ?? fixtureRouteResult(
        for: invocation.selection
    )

    return AgentModelInvocationResult(
        response: response,
        route: AgentModelRouteRecord(
            route: routeResult.route,
            diagnostics: routeResult.diagnostics,
            requestMetadata: invocation.request.metadata,
            responseMetadata: response.metadata,
            usage: response.usage
        )
    )
}

private func fixtureRouteResult(
    for selection: AgentModelSelection
) -> AgentModelRouteResult {
    AgentModelRouteResult(
        route: AgentModelRoute(
            purpose: selection.purpose,
            profile: AgentModelProfile(
                identifier: "fixture.model-profile",
                adapterIdentifier: "fixture.model-adapter",
                model: "fixture-model",
                purposes: [
                    selection.purpose,
                ],
                capabilities: [
                    .text,
                    .reasoning,
                    .structured_output,
                ]
            )
        )
    )
}
