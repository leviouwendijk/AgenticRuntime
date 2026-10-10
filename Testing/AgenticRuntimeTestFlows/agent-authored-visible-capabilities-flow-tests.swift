import Agentic
import AgenticRuntime
import Macros
import Schema
import TestFlows
import Workspace

@JSONSchema
private struct AuthoredVisibleFixtureValue:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct AuthoredVisibleSearchTool:
    Tool
{
    typealias Input = AuthoredVisibleFixtureValue
    typealias Output = AuthoredVisibleFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.authored_visible.search",
        purpose: "Authored-visible search tool.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        input
    }
}

private struct AuthoredVisibleReadTool:
    Tool
{
    typealias Input = AuthoredVisibleFixtureValue
    typealias Output = AuthoredVisibleFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.authored_visible.read",
        purpose: "Authored-visible read tool.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        input
    }
}

private struct AuthoredVisibleMutateTool:
    Tool
{
    typealias Input = AuthoredVisibleFixtureValue
    typealias Output = AuthoredVisibleFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.authored_visible.mutate",
        purpose: "Authored-visible mutate tool.",
        risk: .boundedmutate
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        input
    }
}

private struct AuthoredVisibleBuildTool:
    Tool
{
    typealias Input = AuthoredVisibleFixtureValue
    typealias Output = AuthoredVisibleFixtureValue

    static let definition = ToolDefinition(
        identifier: "fixture.authored_visible.build",
        purpose: "Available-but-hidden build tool.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        input
    }
}

private enum AuthoredVisibleRootFixture:
    Agent
{
    typealias Input = AuthoredVisibleFixtureValue
    typealias Output = AuthoredVisibleFixtureValue

    static let purpose =
        "Proves authored visible capabilities survive a mode-based runtime launch."

    static let capabilities = AgentCapabilities(
        available: .init(
            tools: .init(
                members: [
                    AuthoredVisibleSearchTool.definition.identifier,
                    AuthoredVisibleReadTool.definition.identifier,
                    AuthoredVisibleMutateTool.definition.identifier,
                    AuthoredVisibleBuildTool.definition.identifier,
                ]
            )
        ),
        visible: .init(
            tools: .init(
                members: [
                    AuthoredVisibleSearchTool.definition.identifier,
                    AuthoredVisibleReadTool.definition.identifier,
                    AuthoredVisibleMutateTool.definition.identifier,
                ]
            )
        )
    )

    static let modelSelection = AgentModelSelection(
        purpose: .coder
    )

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(
            rawValue: "fixture.authored_visible.root"
        ),
        purpose: purpose,
        capabilities: capabilities,
        modelSelection: modelSelection
    )
}

private actor AuthoredVisibleRecorder {
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

private struct AuthoredVisibleModelInvoker:
    AgentModelInvoking
{
    let recorder: AuthoredVisibleRecorder

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocation.Result {
        await recorder.append(
            invocation
        )

        return AuthoredVisibleModelInvoker.result(
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
                        AuthoredVisibleModelInvoker.result(
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

    private static func result(
        for invocation: AgentModelInvocation
    ) -> AgentModelInvocation.Result {
        let response = AgentResponse(
            message: Message(
                role: .assistant,
                text: "fixture-authored-visible-response"
            ),
            stopReason: .end_turn,
            metadata: [
                "fixture": "authored-visible",
            ]
        )
        let profile = AgentModelProfile(
            identifier: "fixture.authored_visible.profile",
            gatewayIdentifier: "fixture.authored_visible.gateway",
            model: "fixture-authored-visible-model",
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
    static func runAuthoredVisibleCapabilitiesSurviveLaunch()
        async throws
        -> [TestDiagnostic]
    {
        let application = Agentic.application(
            "fixture.authored_visible"
        ) {
            install(
                AuthoredVisibleSearchTool()
            )
            install(
                AuthoredVisibleReadTool()
            )
            install(
                AuthoredVisibleMutateTool()
            )
            install(
                AuthoredVisibleBuildTool()
            )
            install(
                AuthoredVisibleRootFixture.self
            )
        }
        let runtime = try await AgenticRuntime(
            application: application
        )
        let recorder = AuthoredVisibleRecorder()
        let model = RuntimeServices.Model(
            invoker: AuthoredVisibleModelInvoker(
                recorder: recorder
            ),
            selection: .executor
        )
        let mode = Mode(
            id: "fixture-coder-mode",
            title: "Fixture coder",
            routeDefaults: .init(
                primaryPurpose: .coder,
                selections: [
                    .coder: AgentModelSelection.coder,
                ]
            ),
            autonomyMode: .auto_observe,
            exposedToolIdentifiers: [
                AuthoredVisibleReadTool.definition.identifier,
                AuthoredVisibleMutateTool.definition.identifier,
            ]
        )
        let selection = ModeSelection(
            mode: mode
        )

        let runner = try runtime.makeModeAgentRunner(
            identifiedBy:
                AuthoredVisibleRootFixture
                .definition
                .identifier,
            model: model,
            selection: selection
        )
        let capabilityState =
            await runner.capabilityState
        let snapshot =
            await capabilityState.snapshot()

        // Acceptance #1: explicitly authored visible tools are visible on launch.
        try Expect.equal(
            snapshot.visible.tools
                .map(\.rawValue)
                .sorted(),
            [
                AuthoredVisibleMutateTool.definition.identifier,
                AuthoredVisibleReadTool.definition.identifier,
                AuthoredVisibleSearchTool.definition.identifier,
            ]
            .map(\.rawValue)
            .sorted(),
            "Authored visible tools survive a mode-based runtime launch and are not replaced by mode exposure defaults."
        )

        // The actual first model invocation must use Agent-authored visibility.
        _ = try await runner.run(
            AgentRequest(messages: [Message(role: .user, text: "first")]),
            sessionID: "fixture-authored-visible-first"
        )
        let firstInvocations = await recorder.snapshot()
        try Expect.equal(
            firstInvocations.count,
            1,
            "The initial model invocation was actually performed."
        )
        try Expect.equal(
            firstInvocations[0].request.tools.map(\.identifier).map(\.rawValue).sorted(),
            snapshot.visible.tools.map(\.rawValue).sorted(),
            "First model request projects exactly the Agent-authored visible Tools."
        )

        // The model receives no authority to guess an available-but-hidden
        // Tool that was absent from this exact request's function definitions.
        let guessedCall = ToolCall(
            id: "fixture-unadvertised-guessed-call",
            tool: AuthoredVisibleBuildTool.definition.identifier,
            input: .object(["value": .string("guessed")])
        )
        var guessedModelToolRejected = false
        if let resolver = firstInvocations[0].context.toolCallResolver {
            do {
                _ = try await resolver.resolve(guessedCall)
            } catch AgentToolCallResolutionError.toolNotVisible {
                guessedModelToolRejected = true
            }
        }
        try Expect.equal(
            guessedModelToolRejected,
            true,
            "An actually available hidden Tool is not callable through an unadvertised model function."
        )

        // Acceptance #4: available-but-hidden tools remain hidden until reveal.
        try Expect.equal(
            snapshot.available.tools.contains(
                AuthoredVisibleBuildTool.definition.identifier
            ),
            true,
            "Available-but-hidden build tool remains available."
        )
        try Expect.equal(
            snapshot.visible.tools.contains(
                AuthoredVisibleBuildTool.definition.identifier
            ),
            false,
            "Available-but-hidden build tool is not visible until discovery/reveal."
        )

        // Acceptance #2/#6: reveal promotes an available capability to visible
        // and updates the subsequent live state.
        let revealed =
            await capabilityState.reveal(
                .init(
                    tools: [
                        AuthoredVisibleBuildTool.definition.identifier,
                    ]
                )
            )
        try Expect.equal(
            revealed.tools.contains(
                AuthoredVisibleBuildTool.definition.identifier
            ),
            true,
            "Revealing the build tool promotes it into the live visible set."
        )

        // Previously captured request mappings cannot gain authority later.
        var guessedAfterRevealRejected = false
        if let resolver = firstInvocations[0].context.toolCallResolver {
            do {
                _ = try await resolver.resolve(guessedCall)
            } catch AgentToolCallResolutionError.toolNotVisible {
                guessedAfterRevealRejected = true
            }
        }
        try Expect.equal(guessedAfterRevealRejected, true,
            "Revealing a Tool later cannot retroactively extend an earlier model request.")

        let afterReveal =
            await capabilityState.snapshot()
        try Expect.equal(
            afterReveal.visible.tools.contains(
                AuthoredVisibleBuildTool.definition.identifier
            ),
            true,
            "After reveal, the build tool is part of the live visible set."
        )

        // A subsequent request and a genuinely reselected runner must both
        // use the same live authority rather than the Mode's initial selection.
        _ = try await runner.run(
            AgentRequest(messages: [Message(role: .user, text: "after reveal")]),
            sessionID: "fixture-authored-visible-revealed"
        )
        let reselected = AgentRunner(
            model: model.selecting(.reviewer),
            tooling: .init(registry: runtime.tools),
            inventory: CapabilityInventory(
                installed: runtime.installed,
                state: capabilityState
            )
        )
        _ = try await reselected.run(
            AgentRequest(messages: [Message(role: .user, text: "after reselect")]),
            sessionID: "fixture-authored-visible-reselected"
        )
        try Expect.equal(
            await reselected.capabilityState === capabilityState,
            true,
            "Runner capability state is derived from its inventory."
        )
        let afterReselect = await capabilityState.snapshot()
        let allInvocations = await recorder.snapshot()
        try Expect.equal(
            allInvocations.count,
            3,
            "Initial, revealed, and reselected requests all execute."
        )
        for invocation in allInvocations.dropFirst() {
            try Expect.equal(
                invocation.request.tools.map(\.identifier).map(\.rawValue).sorted(),
                afterReselect.visible.tools.map(\.rawValue).sorted(),
                "Requests after reveal or model reselection project live visibility."
            )
        }
        try Expect.equal(
            allInvocations[2].selection,
            .reviewer,
            "The final request actually uses the reselected model purpose."
        )

        return [
            .field(
                "visible_tools",
                String(
                    snapshot.visible.tools.count
                )
            ),
            .field("guessed_model_tool_rejected", String(guessedModelToolRejected)),
            .field("stale_model_grant_rejected", String(guessedAfterRevealRejected)),
            .field(
                "revealed_build",
                String(
                    revealed.tools.contains(
                        AuthoredVisibleBuildTool.definition.identifier
                    )
                )
            ),
            .field(
                "model_reselection_preserves_visibility",
                String(
                    afterReselect.visible.tools.contains(
                        AuthoredVisibleBuildTool.definition.identifier
                    )
                )
            ),
        ]
    }
}
