import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runUsageAbsorptionCostTracker() throws -> [TestDiagnostic] {
        let firstPrice = try ModelPricingSnapshot.tokenPricing(
            provider: "fixture.provider",
            model: "fixture.first",
            currencyCode: "EUR",
            inputMicrosPerMillionTokens: 2_000_000,
            outputMicrosPerMillionTokens: 4_000_000
        )
        let secondPrice = try ModelPricingSnapshot.tokenPricing(
            provider: "fixture.provider",
            model: "fixture.second",
            currencyCode: "EUR",
            inputMicrosPerMillionTokens: 5_000_000,
            outputMicrosPerMillionTokens: 9_000_000
        )
        let tracker = AgentCostTracker(
            catalog: StaticModelPricingCatalog(snapshots: [firstPrice, secondPrice]),
            reservedOutputTokens: 32
        )
        let request = AgentRequest(messages: [
            Message(role: .user, text: "Estimate a small request"),
        ])

        func route(_ wireModel: String) -> AgentModelRoute {
            .init(
                purpose: .executor,
                profile: .init(
                    identifier: .init(rawValue: "fixture_" + wireModel),
                    gatewayIdentifier: .init(rawValue: "fixture_gateway"),
                    model: wireModel,
                    metadata: ["provider": "fixture.provider"]
                )
            )
        }

        func response(_ model: String, usage: AgentUsage? = .init(
            inputTokens: 47, outputTokens: 17
        )) -> AgentResponse {
            .init(
                message: Message(role: .assistant, text: "response"),
                stopReason: .end_turn,
                usage: usage,
                metadata: ["model": model]
            )
        }

        let firstRoute = route("fixture.first")
        let firstProjected = tracker.projectedRecord(
            existing: nil,
            request: request,
            route: firstRoute,
            sessionID: "routing-session",
            turnIndex: 0
        )
        let firstActual = tracker.actualRecord(
            existing: firstProjected,
            response: response("fixture.first"),
            route: .init(route: firstRoute),
            sessionID: "routing-session",
            turnIndex: 0
        )
        try Expect.equal(firstActual?.turns.count, 1, "Actual updates the same turn")
        try Expect.equal(firstActual?.actual?.pricing?.model, "fixture.first", "First route priced")

        let secondRoute = route("fixture.second")
        let secondProjected = tracker.projectedRecord(
            existing: firstActual,
            request: request,
            route: secondRoute,
            sessionID: "routing-session",
            turnIndex: 1
        )
        let secondActual = tracker.actualRecord(
            existing: secondProjected,
            response: response("fixture.second"),
            route: .init(route: secondRoute),
            sessionID: "routing-session",
            turnIndex: 1
        )
        try Expect.equal(secondActual?.turns.count, 2, "Model switches retain both turns")
        try Expect.equal(secondActual?.turns[0].actual?.pricing?.model, "fixture.first", "First turn preserved")
        try Expect.equal(secondActual?.turns[1].actual?.pricing?.model, "fixture.second", "Second turn priced independently")
        try Expect.equal(secondActual?.turns[1].actual?.usage.inputTokens, 47, "Reported usage retained")

        let autoRoute = route("hyai/auto")
        let autoProjected = tracker.projectedRecord(
            existing: nil,
            request: request,
            route: autoRoute,
            sessionID: "auto-session",
            turnIndex: 0
        )
        try Expect.equal(autoProjected.projected?.status, .unavailable, "Auto has no invented fixed price")
        let autoActual = tracker.actualRecord(
            existing: autoProjected,
            response: response("fixture.second"),
            route: .init(route: autoRoute),
            sessionID: "auto-session",
            turnIndex: 0
        )
        try Expect.equal(autoActual?.actual?.pricing?.model, "fixture.second", "Auto uses physical billed model")
        try Expect.equal(autoActual?.turns[0].requestModel, "hyai/auto", "Requested identity retained")

        let noUsage = tracker.actualRecord(
            existing: secondProjected,
            response: response("fixture.second", usage: nil),
            route: .init(route: secondRoute),
            sessionID: "routing-session",
            turnIndex: 1
        )
        try Expect.equal(noUsage, secondProjected, "Missing usage does not invent actual cost")

        let missing = tracker.actualRecord(
            existing: autoProjected,
            response: response("unknown-physical-model"),
            route: .init(route: autoRoute),
            sessionID: "auto-session",
            turnIndex: 0
        )
        try Expect.equal(missing?.actual?.status, .unavailable, "Unknown billed models remain unpriced")

        return [
            .field("turns", String(secondActual?.turns.count ?? 0)),
            .field("model_switch_priced", "true"),
            .field("auto_resolved", "true"),
            .field("unpriced_unavailable", "true"),
        ]
    }
}
