import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runApplicationGatewayAvailability()
        async throws
        -> [TestDiagnostic]
    {
        let identifier = AgentModelGatewayIdentifier(
            "fixture.application.unavailable"
        )
        let probe = ApplicationGatewayResolutionProbe()
        let factory = AgentModelGatewayFactory(
            identifier: identifier,
            resolve: {
                await probe.recordResolution()

                return .unavailable(
                    .init(
                        kind: .missing_configuration,
                        message: "Fixture gateway is not configured.",
                        metadata: [
                            "fixture": "application",
                        ]
                    )
                )
            }
        )
        let application = Agentic.application(
            "fixture.application_gateway_availability"
        ) {
            factory
            modelProvider(ApplicationPricingFixtureModelProvider())
        }

        let runtime = try await AgenticRuntime(
            application: application
        )
        let resolutionCount = await probe.resolutionCount
        let price = try runtime.pricing.pricing(
            for: .init(
                provider: "fixture.pricing",
                model: "fixture-model"
            )
        )

        try Expect.equal(
            price.currencyCode,
            "EUR",
            "Runtime exposes pricing composed from installed model providers"
        )

        try Expect.equal(
            resolutionCount,
            1,
            "application-authored gateway factory is resolved exactly once by the model catalog boundary"
        )
        try Expect.equal(
            runtime.gateways.contains(identifier),
            true,
            "known unavailable application gateway remains represented in Runtime"
        )
        try Expect.equal(
            runtime.gateways.unavailability(
                for: identifier
            )?.kind,
            .missing_configuration,
            "Runtime construction preserves structured gateway unavailability"
        )
        try Expect.equal(
            runtime.gateways.gatewaysByIdentifier[identifier] == nil,
            true,
            "unavailable application gateway is not realized as an invokable gateway"
        )

        return [
            .field(
                "gateway",
                identifier.rawValue
            ),
            .field(
                "resolutions",
                String(resolutionCount)
            ),
            .field(
                "availability",
                "unavailable"
            ),
        ]
    }
}

private struct ApplicationPricingFixtureModelProvider: AgentModelProvider {
    let descriptor = AgentModelProviderDescriptor(
        source: "fixture.pricing",
        displayName: "Pricing fixture"
    )

    func pricingSnapshots() throws -> [ModelPricingSnapshot] {
        [
            try .tokenPricing(
                provider: "fixture.pricing",
                model: "fixture-model",
                currencyCode: "EUR",
                inputMicrosPerMillionTokens: 100000,
                outputMicrosPerMillionTokens: 200000
            ),
        ]
    }
}

private actor ApplicationGatewayResolutionProbe {
    private(set) var resolutionCount = 0

    func recordResolution() {
        resolutionCount += 1
    }
}
