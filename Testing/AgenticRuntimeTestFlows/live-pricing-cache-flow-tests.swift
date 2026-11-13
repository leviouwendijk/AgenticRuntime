import Agentic
import AgenticRuntime
import Foundation
import IO
import TestFlows

private actor LivePricingFixture {
    private(set) var fetches = 0
    var failing = false
    var inputMicros: Int64 = 290_000

    func fetch() throws -> [ModelPricingSnapshot] {
        fetches += 1
        if failing { throw URLError(.notConnectedToInternet) }
        return [try .tokenPricing(
            provider: "fixture",
            model: "fixture/model",
            source: .live,
            currencyCode: "EUR",
            inputMicrosPerMillionTokens: inputMicros,
            outputMicrosPerMillionTokens: 350_000,
            cachedInputReadMicrosPerMillionTokens: 70_000
        )]
    }

    func set(failing: Bool, inputMicros: Int64) {
        self.failing = failing
        self.inputMicros = inputMicros
    }
}

private struct LivePricingFixtureProvider: AgentModelProvider {
    let descriptor = AgentModelProviderDescriptor(source: "fixture", displayName: "Fixture")
    let fixture: LivePricingFixture

    func livePricing() async throws -> [ModelPricingSnapshot] {
        try await fixture.fetch()
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runLivePricingCache() async throws -> [TestDiagnostic] {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("live-pricing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileSystem.default.remove(root) }
        let fixture = LivePricingFixture()
        let provider = LivePricingFixtureProvider(fixture: fixture)
        let cache = LivePricingCache(directory: root, maximumAge: 60)
        let start = Date()

        func input(_ snapshots: [ModelPricingSnapshot]) -> Int64? {
            snapshots.first?.component(.inputTokens)?.priceMicros
        }

        let first = await cache.snapshots(for: [provider], now: start)
        try Expect.equal(input(first), 290_000, "A missing cache is fetched")
        try Expect.equal(await fixture.fetches, 1, "One fetch fills the cache")

        let fresh = await cache.snapshots(for: [provider], now: start.addingTimeInterval(30))
        try Expect.equal(input(fresh), 290_000, "A fresh cache is used")
        try Expect.equal(await fixture.fetches, 1, "A fresh cache is not refetched")

        await fixture.set(failing: false, inputMicros: 310_000)
        let refreshed = await cache.snapshots(for: [provider], now: start.addingTimeInterval(120))
        try Expect.equal(input(refreshed), 310_000, "A stale cache is refreshed")

        await fixture.set(failing: true, inputMicros: 999_000)
        let offline = await cache.snapshots(for: [provider], now: start.addingTimeInterval(400))
        try Expect.equal(input(offline), 310_000, "A failed refresh keeps the last known prices")

        let catalog = StaticModelPricingCatalog(snapshots: offline)
        let billed = try catalog.pricing(for: .init(provider: "fixture", model: "other-org/MODEL"))
        try Expect.equal(billed.model, "fixture/model", "Billed names resolve across prefix and case")
        return [.field("fetches", String(await fixture.fetches))]
    }
}
