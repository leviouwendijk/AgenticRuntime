import Agentic
import AgenticRuntime
import Macros
import Schema
import TestFlows
import Workspace

@JSONSchema
private struct AgentInvocationFixtureValue:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct AgentInvocationAllowedTool:
    Tool
{
    typealias Input = AgentInvocationFixtureValue
    typealias Output = AgentInvocationFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.agent_invocation.allowed",
        purpose: "Allowed Tool for Agent invocation authority.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        input
    }
}

private struct AgentInvocationExcludedTool:
    Tool
{
    typealias Input = AgentInvocationFixtureValue
    typealias Output = AgentInvocationFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.agent_invocation.excluded",
        purpose: "Installed Tool excluded from Agent invocation authority.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        input
    }
}

private enum AgentInvocationRootFixture:
    Agent
{
    typealias Input = AgentInvocationFixtureValue
    typealias Output = AgentInvocationFixtureValue

    static let purpose =
        "Proves realized Agent policy governs actual model invocation."

    static let capabilities = AgentCapabilities(
        available: .init(
            tools: .init(
                members: [
                    AgentInvocationAllowedTool.definition.identifier,
                    AgentInvocationExcludedTool.definition.identifier,
                ]
            )
        ),
        visible: .init(
            tools: .init(
                members: [
                    AgentInvocationAllowedTool.definition.identifier,
                ]
            )
        )
    )

    static let modelSelection = AgentModelSelection(
        purpose: .coder
    )

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(
            rawValue: "fixture.agent_invocation.root"
        ),
        purpose: purpose,
        capabilities: capabilities,
        modelSelection: modelSelection
    )
}

private actor AgentInvocationRecorder {
    private var invocations:
        [AgentModelInvocation] = []

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

private struct AgentInvocationModelInvoker:
    AgentModelInvoking
{
    let recorder: AgentInvocationRecorder

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocation.Result {
        await recorder.append(
            invocation
        )

        return result(
            for: invocation
        )
    }

    func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<
        AgentModelInvocation.Event,
        Error
    > {
        AsyncThrowingStream { continuation in
            let task = Task {
                await recorder.append(
                    invocation
                )

                continuation.yield(
                    .completed(
                        result(
                            for: invocation
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

    private func result(
        for invocation: AgentModelInvocation
    ) -> AgentModelInvocation.Result {
        let response = AgentResponse(
            message: Message(
                role: .assistant,
                text: "fixture-agent-response"
            ),
            stopReason: .end_turn,
            metadata: [
                "fixture": "agent-invocation",
            ]
        )
        let profile = AgentModelProfile(
            identifier: "fixture.agent_invocation.profile",
            gatewayIdentifier: "fixture.agent_invocation.gateway",
            model: "fixture-agent-model",
            purposes: [
                invocation.selection.purpose,
            ],
            capabilities: [
                .text,
                .reasoning,
                .structured_output,
            ]
        )
        let route = AgentModelRoute(
            purpose: invocation.selection.purpose,
            profile: profile
        )

        return AgentModelInvocation.Result(
            response: response,
            route: AgentModelRouteRecord(
                route: route,
                requestMetadata: invocation.metadata,
                responseMetadata: response.metadata,
                usage: response.usage
            )
        )
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runAgentInvocation()
        async throws
        -> [TestDiagnostic]
    {
        let application = Agentic.application(
            "fixture.agent_invocation"
        ) {
            install(
                AgentInvocationAllowedTool()
            )
            install(
                AgentInvocationExcludedTool()
            )
            install(
                AgentInvocationRootFixture.self
            )
        }
        let runtime = try await AgenticRuntime(
            application: application
        )
        let recorder = AgentInvocationRecorder()
        let model = RuntimeServices.Model(
            invoker: AgentInvocationModelInvoker(
                recorder: recorder
            ),
            selection: .executor
        )
        var baselineConfiguration =
            AgentRunner.Configuration.default
        baselineConfiguration.autonomyMode =
            .auto_observe

        let runner = try runtime.makeAgentRunner(
            identifiedBy:
                AgentInvocationRootFixture
                .definition
                .identifier,
            model: model,
            configuration: baselineConfiguration
        )
        let runnerConfiguration =
            await runner.configuration
        let runnerModel =
            await runner.model

        let runnerCapabilityState =
            await runner.capabilityState

        let runnerCapabilitySnapshot =
            await runnerCapabilityState.snapshot()

        try Expect.equal(
            runnerCapabilitySnapshot.available.tools,
            [
                AgentInvocationAllowedTool.definition.identifier,
                AgentInvocationExcludedTool.definition.identifier,
            ],
            "Root Agent runner carries realized generic availability as live state"
        )
        try Expect.equal(
            runnerCapabilitySnapshot.visible.tools,
            [
                AgentInvocationAllowedTool.definition.identifier,
            ],
            "Root Agent runner carries realized generic visibility as live state"
        )

        try Expect.equal(
            runnerConfiguration.autonomyMode,
            .auto_observe,
            "Agent realization preserves unrelated invocation configuration overrides"
        )
        try Expect.equal(
            runnerModel.selection,
            AgentInvocationRootFixture.modelSelection,
            "Root Agent runner replaces the caller's baseline model selection with the Agent's authored selection"
        )

        let result = try await runtime.runAgent(
            identifiedBy:
                AgentInvocationRootFixture
                .definition
                .identifier,
            request: AgentRequest(
                messages: [
                    Message(
                        role: .user,
                        text: "invoke the realized root Agent"
                    ),
                ]
            ),
            model: model,
            configuration: baselineConfiguration,
            sessionID: "fixture-agent-invocation"
        )
        let invocations = await recorder.snapshot()

        try Expect.equal(
            invocations.count,
            1,
            "Runtime executes one model turn through the realized root Agent"
        )

        guard let invocation = invocations.first else {
            fatalError(
                "Expected one recorded root Agent model invocation."
            )
        }

        try Expect.equal(
            invocation.selection,
            AgentInvocationRootFixture.modelSelection,
            "Actual model invocation uses the Agent's authored model selection"
        )
        try Expect.equal(
            invocation.request.tools.map(\.identifier),
            [
                AgentInvocationAllowedTool.definition.identifier,
            ],
            "Actual model invocation exposes only visible Tools, while hidden available Tools remain authorized but out of context"
        )
        try Expect.equal(
            result.response?.message.content.text,
            "fixture-agent-response",
            "Runtime returns the response produced through the realized root Agent"
        )

        // The semantic dispatcher must route a trusted Host Agent invocation
        // through the same realized runner, rather than treating Agent as a
        // permanent unsupported capability kind.
        let dispatcher = CapabilityDispatcher(
            runtime: runtime,
            capabilityState: AgentCapabilityState(
                installed: runtime.installed.capabilities
            ),
            services: RuntimeServices(model: model),
            configuration: baselineConfiguration
        )
        let hostOutcome = try await dispatcher.invoke(
            .agent(
                identifier: AgentInvocationRootFixture.definition.identifier,
                request: AgentRequest(messages: [
                    Message(role: .user, text: "invoke through capability dispatcher")
                ]),
                sessionID: "fixture-dispatched-root-agent"
            ),
            origin: .host
        )
        guard case .agent(let dispatchedResult) = hostOutcome else {
            try Expect.equal(false, true, "Host Agent invocation must return Agent outcome")
            return []
        }
        try Expect.equal(
            dispatchedResult.sessionID,
            "fixture-dispatched-root-agent",
            "Host Agent dispatch preserves explicitly supplied run identity"
        )
        try Expect.equal(
            dispatchedResult.response?.message.content.text,
            "fixture-agent-response",
            "Host Agent dispatch executes the realized Agent"
        )
        let invocationAfterHostDispatch = await recorder.snapshot()
        try Expect.equal(
            invocationAfterHostDispatch.count,
            2,
            "Host Agent dispatch performs a model turn through the existing invoker"
        )
        try Expect.equal(
            invocationAfterHostDispatch.last?.selection,
            AgentInvocationRootFixture.modelSelection,
            "Dispatched Agent retains authored model routing"
        )
        try Expect.equal(
            invocationAfterHostDispatch.last?.request.tools.map(\.identifier),
            [AgentInvocationAllowedTool.definition.identifier],
            "Dispatched Agent retains its realized visibility boundary"
        )

        var delegationDenied = false
        do {
            _ = try await dispatcher.invoke(
                .agent(
                    identifier: AgentInvocationRootFixture.definition.identifier,
                    request: AgentRequest(messages: []),
                    sessionID: "fixture-unguarded-child"
                ),
                origin: .delegated_agent
            )
        } catch CapabilityInvocationError.agentRequiresDelegation(let identifier) {
            delegationDenied = true
            try Expect.equal(
                identifier,
                AgentInvocationRootFixture.definition.identifier,
                "Unguarded child calls fail with their semantic Agent identifier"
            )
        }
        try Expect.true(delegationDenied, "Unguarded child Agent execution stays fail-closed")
        let invocationsAfterRejectedChild = await recorder.snapshot()
        try Expect.equal(
            invocationsAfterRejectedChild.count,
            2,
            "Refused child Agent invocation must never reach the model"
        )

        let withoutModel = CapabilityDispatcher(
            runtime: runtime,
            capabilityState: AgentCapabilityState(
                installed: runtime.installed.capabilities
            )
        )
        var missingModelDenied = false
        do {
            _ = try await withoutModel.invoke(
                .agent(
                    identifier: AgentInvocationRootFixture.definition.identifier,
                    request: AgentRequest(messages: []),
                    sessionID: "fixture-missing-agent-model"
                ),
                origin: .host
            )
        } catch CapabilityInvocationError.missingAgentModel(let identifier) {
            missingModelDenied = true
            try Expect.equal(
                identifier,
                AgentInvocationRootFixture.definition.identifier,
                "Root Agent invocation reports the exact missing model dependency"
            )
        }
        try Expect.true(missingModelDenied, "Host Agent invocation without model fails closed")

        return [
            .field(
                "model_purpose",
                invocation.selection.purpose.rawValue
            ),
            .field(
                "visible_tools",
                String(
                    invocation
                        .request
                        .tools
                        .count
                )
            ),
            .field(
                "response",
                result
                    .response?
                    .message
                    .content
                    .text
                    ?? "<none>"
            ),
        ]
    }
}
