import Agentic
import Foundation

/// Provider-published prices, cached in the Agentic home: one file per
/// provider (`pricing/live-<provider>.json`), refreshed when older than
/// `maximumAge`. A failed refresh keeps the previous file; with neither, the
/// provider's curated `pricingSnapshots()` stand.
public struct LivePricingCache: Sendable {
    public let directory: URL
    public let maximumAge: TimeInterval

    public init(
        directory: URL,
        maximumAge: TimeInterval = 24 * 60 * 60
    ) {
        self.directory = directory.standardizedFileURL
        self.maximumAge = maximumAge
    }

    /// The home's pricing directory, shared by every project.
    public static func home(
        _ home: AgentHome
    ) -> Self {
        .init(directory: home.root.appendingPathComponent("pricing", isDirectory: true))
    }

    /// Live snapshots of every provider that publishes prices.
    public func snapshots(
        for providers: [any AgentModelProvider],
        now: Date = Date()
    ) async -> [ModelPricingSnapshot] {
        var snapshots: [ModelPricingSnapshot] = []
        for provider in providers {
            snapshots += await self.snapshots(for: provider, now: now)
        }
        return snapshots
    }

    private func snapshots(
        for provider: any AgentModelProvider,
        now: Date
    ) async -> [ModelPricingSnapshot] {
        let file = FileModelPricingCatalog(
            catalogfile: directory.appendingPathComponent(
                "live-\(provider.descriptor.source.rawValue).json"
            )
        )
        let cached = try? file.loadDocument()
        if let cached, !cached.snapshots.isEmpty,
           now.timeIntervalSince(cached.updatedAt) < maximumAge {
            return cached.snapshots
        }

        do {
            let live = try await provider.livePricing()
            guard !live.isEmpty else {
                return cached?.snapshots ?? []
            }
            try? file.saveSnapshots(live)
            return live
        } catch {
            // Offline, unauthorised or unreachable: last known prices.
            return cached?.snapshots ?? []
        }
    }
}
