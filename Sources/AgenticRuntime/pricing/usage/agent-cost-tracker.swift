import Agentic
import Foundation
import Tokens

/// Prices individual invocations against the route that actually executed.
/// There is no session-wide provider or model fallback.
public struct AgentCostTracker: Sendable {
    public let catalog: any ModelPricingCatalog
    public var reservedOutputTokens: Int
    public var estimationOptions: TokenEstimationOptions
    public var metadata: [String: String]

    public init(
        catalog: any ModelPricingCatalog,
        reservedOutputTokens: Int = 0,
        estimationOptions: TokenEstimationOptions = .agenticContext,
        metadata: [String: String] = [:]
    ) {
        self.catalog = catalog
        self.reservedOutputTokens = max(0, reservedOutputTokens)
        self.estimationOptions = estimationOptions
        self.metadata = metadata
    }

    public func projectedRecord(
        existing: AgentCostRecord?,
        request: AgentRequest,
        route: AgentModelRoute,
        sessionID: String,
        turnIndex: Int
    ) -> AgentCostRecord {
        let provider = Self.normalized(route.profile.metadata["provider"])
            ?? Self.normalized(route.metadata["provider"])
        let model = Self.normalized(route.profile.model)
        let region = Self.normalized(route.profile.metadata["region"])
            ?? Self.normalized(route.metadata["region"])
        let metadata = mergedMetadata(
            provider: provider,
            model: model,
            region: region,
            phase: "projected",
            sessionID: sessionID,
            turnIndex: turnIndex
        )

        let projection: AgentCostProjection
        if let provider, let model {
            projection = catalog.projectCost(
                provider: provider,
                model: model,
                region: region,
                inputEstimate: request.estimatedInputTokens(options: estimationOptions),
                reservedOutputTokens: reservedOutputTokens,
                metadata: metadata
            )
        } else {
            projection = AgentCostCalculator.unavailable(
                usage: request.estimatedInputCostUsage(
                    options: estimationOptions,
                    reservedOutputTokens: reservedOutputTokens
                ),
                reason: "Selected model route has no usable pricing provider/model identity.",
                metadata: metadata
            )
        }

        let turn = AgentModelTurnCostRecord(
            turnIndex: turnIndex,
            requestModel: model,
            projected: projection
        )

        if let existing {
            return existing.appendingOrReplacingTurn(turn)
        }

        return .init(
            sessionID: sessionID,
            model: model,
            projected: projection,
            turns: [turn],
            metadata: mergedMetadata(
                provider: provider,
                model: model,
                region: region,
                phase: "record",
                sessionID: sessionID,
                turnIndex: turnIndex
            )
        )
    }

    public func actualRecord(
        existing: AgentCostRecord?,
        response: AgentResponse,
        route: AgentModelRouteRecord,
        sessionID: String,
        turnIndex: Int
    ) -> AgentCostRecord? {
        guard let usage = response.usage else {
            return existing
        }

        let provider = Self.normalized(route.route.profile.metadata["provider"])
            ?? Self.normalized(route.route.metadata["provider"])
            ?? Self.normalized(response.metadata["provider"])
        let requestedModel = Self.normalized(route.route.profile.model)
        // Gateways must identify a physical billed model, especially for virtual/auto.
        let billedModel = Self.normalized(response.metadata["model"])
            ?? requestedModel
        let region = Self.normalized(route.route.profile.metadata["region"])
            ?? Self.normalized(route.route.metadata["region"])
        let metadata = mergedMetadata(
            provider: provider,
            model: billedModel,
            region: region,
            phase: "actual",
            sessionID: sessionID,
            turnIndex: turnIndex
        ).merging(["requested_model": requestedModel ?? ""]) { _, new in new }

        let actual: AgentCostProjection
        if let provider, let billedModel {
            actual = catalog.actualCost(
                provider: provider,
                model: billedModel,
                region: region,
                providerUsage: usage,
                metadata: metadata
            )
        } else {
            actual = AgentCostCalculator.unavailable(
                usage: usage.costUsage,
                reason: "Completed invocation has no usable billed pricing identity.",
                metadata: metadata
            )
        }

        if let existing {
            return existing.updatingTurnActual(
                turnIndex: turnIndex,
                actual: actual
            )
        }

        return .init(
            sessionID: sessionID,
            model: requestedModel,
            actual: actual,
            turns: [
                .init(
                    turnIndex: turnIndex,
                    requestModel: requestedModel,
                    actual: actual
                )
            ],
            metadata: mergedMetadata(
                provider: provider,
                model: requestedModel,
                region: region,
                phase: "record",
                sessionID: sessionID,
                turnIndex: turnIndex
            )
        )
    }
}

private extension AgentCostTracker {
    func mergedMetadata(
        provider: String?,
        model: String?,
        region: String?,
        phase: String,
        sessionID: String,
        turnIndex: Int
    ) -> [String: String] {
        var result = metadata
        result["phase"] = phase
        result["sessionID"] = sessionID
        result["turnIndex"] = String(turnIndex)
        if let provider { result["provider"] = provider }
        if let model { result["model"] = model }
        if let region { result["region"] = region }
        return result
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
