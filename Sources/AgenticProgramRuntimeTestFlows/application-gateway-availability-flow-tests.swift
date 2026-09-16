import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runApplicationGatewayAvailability()
        async throws
        -> [TestFlowDiagnostic]
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
        }

        let runtime = try await AgenticRuntime(
            application: application
        )
        let resolutionCount = await probe.resolutionCount

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

private actor ApplicationGatewayResolutionProbe {
    private(set) var resolutionCount = 0

    func recordResolution() {
        resolutionCount += 1
    }
}
