import Agentic
import AgenticRuntime
import Macros
import Schema
import TestFlows

@JSONSchema
private struct PurposeSelectionFixtureValue:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct PurposeSelectionUnusedInvoker:
    AgentModelInvoking
{
    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocation.Result {
        throw CancellationError()
    }

    func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<
        AgentModelInvocation.Event,
        Error
    > {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: CancellationError()
            )
        }
    }
}

private enum PurposeSelectionCoderFixture:
    Agent
{
    typealias Input = PurposeSelectionFixtureValue
    typealias Output = PurposeSelectionFixtureValue

    static let purpose = "Declares only a route purpose."

    static let modelSelection = AgentModelSelection(
        purpose: .coder
    )

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(
            rawValue: "fixture.purpose_selection.coder"
        ),
        purpose: purpose,
        modelSelection: modelSelection
    )
}

private enum PurposeSelectionReviewerFixture:
    Agent
{
    typealias Input = PurposeSelectionFixtureValue
    typealias Output = PurposeSelectionFixtureValue

    static let purpose = "Declares a purpose the application leaves unbound."

    static let modelSelection = AgentModelSelection(
        purpose: .reviewer
    )

    static let definition = AgentDefinition(
        identifier: AgentIdentifier(
            rawValue: "fixture.purpose_selection.reviewer"
        ),
        purpose: purpose,
        modelSelection: modelSelection
    )
}

extension AgenticProgramRuntimeFlowTesting {
    static func runApplicationPurposeModelSelection()
        async throws
        -> [TestDiagnostic]
    {
        let application = Agentic.application(
            "fixture.purpose_selection"
        ) {
            install(
                PurposeSelectionCoderFixture.self
            )
            install(
                PurposeSelectionReviewerFixture.self
            )
            modelSelection(
                default: .init(
                    latency: .high
                ),
                purposes: [
                    .coder: .init(
                        cost: .cheap
                    ),
                ]
            )
        }
        let runtime = try await AgenticRuntime(
            application: application
        )

        try Expect.equal(
            runtime.application.modelSelection.preferences(for: .coder),
            AgentModelPreferences(
                cost: .cheap,
                latency: .high
            ),
            "A purpose binding layers over the application default"
        )

        // The caller runs under another purpose with its own posture.
        let parent = RuntimeServices.Model(
            invoker: PurposeSelectionUnusedInvoker(),
            selection: .init(
                purpose: .planner,
                preferences: .init(
                    cost: .premium,
                    latency: .low
                )
            )
        )

        let coderExecutor = try runtime.makeAgentExecutor(
            identifiedBy: PurposeSelectionCoderFixture.definition.identifier,
            model: parent
        )
        let coder = await coderExecutor.model.selection
        try Expect.equal(
            coder.purpose,
            .coder,
            "A delegated child keeps its own purpose"
        )
        try Expect.equal(
            coder.preferences.cost,
            .cheap,
            "A bound child purpose starts from the application binding, not the caller's posture"
        )
        try Expect.equal(
            coder.preferences.latency,
            .high,
            "The application default fills what the purpose binding leaves open"
        )

        let reviewerExecutor = try runtime.makeAgentExecutor(
            identifiedBy: PurposeSelectionReviewerFixture.definition.identifier,
            model: parent
        )
        let reviewer = await reviewerExecutor.model.selection
        try Expect.equal(
            reviewer.preferences.cost,
            .premium,
            "An unbound child purpose still inherits the caller's posture"
        )

        let unroutable = Agentic.application(
            "fixture.purpose_selection.unroutable"
        ) {
            modelSelection(
                default: .init(),
                purposes: [
                    .coder: .init(
                        gateways: [
                            "fixture.gateway.missing.first",
                            "fixture.gateway.missing.second",
                        ]
                    ),
                ]
            )
        }
        var rejected = false
        do {
            _ = try await AgenticRuntime(
                application: unroutable
            )
        } catch ApplicationModelSelectionError.unavailable_gateway(let gateway) {
            rejected = true
            try Expect.equal(
                gateway.rawValue,
                "fixture.gateway.missing.first",
                "Startup names the first gateway of an unroutable chain"
            )
        }
        try Expect.true(
            rejected,
            "A purpose binding no gateway can serve fails at startup"
        )

        // An installed model whose gateway is unconfigured: binding without
        // fallback fails at startup, with fallback the runtime starts.
        let unconfiguredModel = AgentModelID(
            rawValue: "fixture:unconfigured"
        )
        let unconfiguredSelection: (Bool) -> AgenticApplication = { allowsFallback in
            Agentic.application(
                "fixture.purpose_selection.unconfigured"
            ) {
                modelProvider(PurposeSelectionUnconfiguredModelProvider())
                modelSelection(
                    default: .init(
                        preferredModelID: unconfiguredModel,
                        gateway: PurposeSelectionUnconfiguredModelProvider.gateway,
                        allowsFallback: allowsFallback
                    )
                )
            }
        }

        var bindingRejected = false
        do {
            _ = try await AgenticRuntime(
                application: unconfiguredSelection(false)
            )
        } catch ApplicationModelSelectionError.unavailable_model(let model, _) {
            bindingRejected = model == unconfiguredModel
        }
        try Expect.true(
            bindingRejected,
            "A binding default on an unconfigured gateway fails at startup"
        )

        let fallback = try await AgenticRuntime(
            application: unconfiguredSelection(true)
        )
        try Expect.equal(
            fallback.gateways.unavailability(
                for: PurposeSelectionUnconfiguredModelProvider.gateway
            )?.kind,
            .missing_configuration,
            "A fallback default on an unconfigured gateway starts and keeps the gateway unavailable"
        )

        let misnamed = Agentic.application(
            "fixture.purpose_selection.misnamed"
        ) {
            modelProvider(PurposeSelectionUnconfiguredModelProvider())
            modelSelection(
                default: .init(
                    preferredModelID: AgentModelID(
                        rawValue: "fixture:misnamed"
                    ),
                    allowsFallback: true
                )
            )
        }
        var misnamedRejected = false
        do {
            _ = try await AgenticRuntime(
                application: misnamed
            )
        } catch ApplicationModelSelectionError.unavailable_model {
            misnamedRejected = true
        }
        try Expect.true(
            misnamedRejected,
            "A fallback default must still name an installed model"
        )

        return [
            .field(
                "coder_cost",
                coder.preferences.cost?.rawValue ?? "<none>"
            ),
        ]
    }
}

private struct PurposeSelectionUnconfiguredModelProvider:
    AgentModelProvider
{
    static let gateway = AgentModelGatewayIdentifier(
        "fixture.purpose_selection.unconfigured"
    )

    let descriptor = AgentModelProviderDescriptor(
        source: "fixture.purpose_selection.unconfigured",
        displayName: "Unconfigured fixture"
    )

    var gateways: [AgentModelGatewayFactory] {
        [
            .init(
                identifier: Self.gateway,
                resolve: {
                    .unavailable(
                        .init(
                            kind: .missing_configuration,
                            message: "Fixture key is not configured."
                        )
                    )
                }
            ),
        ]
    }

    var profileProviders: [any AgentModelProfileProvider] {
        [
            SnapshotAgentModelProfileProvider(
                snapshot: .init(
                    source: "fixture.purpose_selection.unconfigured",
                    profiles: [
                        AgentModelProfile(
                            identifier: "fixture.purpose_selection.unconfigured",
                            gatewayIdentifier: Self.gateway,
                            model: "unconfigured",
                            modelID: AgentModelID(
                                rawValue: "fixture:unconfigured"
                            )
                        ),
                    ]
                )
            ),
        ]
    }
}
