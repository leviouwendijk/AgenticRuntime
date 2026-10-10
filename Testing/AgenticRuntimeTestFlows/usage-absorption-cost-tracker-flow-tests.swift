import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runUsageAbsorptionCostTracker() throws -> [TestDiagnostic] {
        let pricing = try ModelPricingSnapshot.tokenPricing(
            provider: "fixture.provider",
            model: "fixture.model",
            currencyCode: "USD",
            inputMicrosPerMillionTokens: 2_000_000,
            outputMicrosPerMillionTokens: 4_000_000
        )
        let tracker = AgentCostTracker(
            catalog: StaticModelPricingCatalog(snapshots: [pricing]),
            provider: "fixture.provider",
            defaultModel: "fixture.model",
            reservedOutputTokens: 32
        )
        let request = AgentRequest(
            messages: [
                Message(role: .user, text: "Estimate a small request"),
            ]
        )
        let projected = tracker.projectedRecord(
            existing: nil,
            request: request,
            sessionID: "usage-migration-session",
            turnIndex: 0
        )

        try Expect.equal(
            projected.turns.count,
            1,
            "projected record retains one turn"
        )
        try Expect.equal(
            projected.turns.first?.requestModel,
            "fixture.model",
            "tracker retains configured request model"
        )
        try Expect.equal(
            projected.projected?.status,
            .available,
            "token-based projection resolves catalog pricing"
        )
        try Expect.equal(
            projected.projected?.usage.outputTokens,
            32,
            "reserved output token estimate is preserved"
        )

        let response = AgentResponse(
            message: Message(role: .assistant, text: "response"),
            stopReason: .end_turn,
            usage: AgentUsage(inputTokens: 47, outputTokens: 17)
        )
        let actual = tracker.actualRecord(
            existing: projected,
            request: request,
            response: response,
            sessionID: "usage-migration-session",
            turnIndex: 0
        )

        try Expect.equal(
            actual?.turns.count,
            1,
            "actual accounting updates the same turn instead of duplicating it"
        )
        try Expect.equal(
            actual?.actual?.status,
            .available,
            "actual usage resolves catalog pricing"
        )
        try Expect.equal(
            actual?.actual?.usage.inputTokens,
            47,
            "provider-reported input usage is retained"
        )
        try Expect.equal(
            actual?.actual?.usage.outputTokens,
            17,
            "provider-reported output usage is retained"
        )
        try Expect.equal(
            actual?.metadata["provider"],
            "fixture.provider",
            "provider metadata survives migration"
        )

        let withoutUsage = AgentResponse(
            message: Message(role: .assistant, text: "no usage"),
            stopReason: .end_turn
        )
        let retained = tracker.actualRecord(
            existing: projected,
            request: request,
            response: withoutUsage,
            sessionID: "usage-migration-session",
            turnIndex: 0
        )
        try Expect.equal(
            retained,
            projected,
            "missing provider usage does not erase projected records"
        )

        let missingPricingTracker = AgentCostTracker(
            catalog: StaticModelPricingCatalog(),
            provider: "fixture.provider",
            defaultModel: "unpriced.model"
        )
        let missingPricing = missingPricingTracker.projectedRecord(
            existing: nil,
            request: request,
            sessionID: "usage-migration-unpriced",
            turnIndex: 0
        )
        try Expect.equal(
            missingPricing.projected?.status,
            .unavailable,
            "missing pricing remains an explicit unavailable projection"
        )

        return [
            .field("projected_turns", String(projected.turns.count)),
            .field("actual_input_tokens", String(actual?.actual?.usage.inputTokens ?? 0)),
            .field("missing_pricing_unavailable", String(missingPricing.projected?.status == .unavailable)),
        ]
    }
}
