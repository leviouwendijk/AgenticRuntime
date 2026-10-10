import Agentic
import Foundation
import Tokens

public struct AgentCostTracker: Sendable {
    public let catalog: any ModelPricingCatalog
    public var provider: String
    public var region: String?
    public var defaultModel: String?
    public var reservedOutputTokens: Int
    public var estimationOptions: TokenEstimationOptions
    public var metadata: [String: String]

    public init(
        catalog: any ModelPricingCatalog,
        provider: String,
        region: String? = nil,
        defaultModel: String? = nil,
        reservedOutputTokens: Int = 0,
        estimationOptions: TokenEstimationOptions = .agenticContext,
        metadata: [String: String] = [:]
    ) {
        self.catalog = catalog
        self.provider = provider
        self.region = Self.normalized(
            region
        )
        self.defaultModel = Self.normalized(
            defaultModel
        )
        self.reservedOutputTokens = max(
            0,
            reservedOutputTokens
        )
        self.estimationOptions = estimationOptions
        self.metadata = metadata
    }

    public func projectedRecord(
        existing: AgentCostRecord?,
        request: AgentRequest,
        sessionID: String,
        turnIndex: Int
    ) -> AgentCostRecord {
        let model = resolvedModel()

        let projection: AgentCostProjection
        if let model {
            let estimate = request.estimatedInputTokens(
                options: estimationOptions
            )

            projection = catalog.projectCost(
                provider: provider,
                model: model,
                region: region,
                inputEstimate: estimate,
                reservedOutputTokens: reservedOutputTokens,
                metadata: mergedMetadata(
                    [
                        "phase": "projected",
                        "sessionID": sessionID,
                        "turnIndex": "\(turnIndex)"
                    ]
                )
            )
        } else {
            projection = AgentCostCalculator.unavailable(
                usage: request.estimatedInputCostUsage(
                    options: estimationOptions,
                    reservedOutputTokens: reservedOutputTokens
                ),
                reason: "No default model was configured on the cost tracker.",
                metadata: mergedMetadata(
                    [
                        "phase": "projected",
                        "sessionID": sessionID,
                        "turnIndex": "\(turnIndex)"
                    ]
                )
            )
        }

        let turn = AgentModelTurnCostRecord(
            turnIndex: turnIndex,
            requestModel: model,
            projected: projection
        )

        if let existing {
            return existing.appendingOrReplacingTurn(
                turn
            )
        }

        return .init(
            sessionID: sessionID,
            model: model,
            projected: projection,
            turns: [
                turn
            ],
            metadata: mergedMetadata(
                [
                    "provider": provider
                ]
            )
        )
    }

    public func actualRecord(
        existing: AgentCostRecord?,
        request: AgentRequest,
        response: AgentResponse,
        sessionID: String,
        turnIndex: Int
    ) -> AgentCostRecord? {
        guard let usage = response.usage else {
            return existing
        }

        let model = resolvedModel()

        let actual: AgentCostProjection
        if let model {
            actual = catalog.actualCost(
                provider: provider,
                model: model,
                region: region,
                providerUsage: usage,
                metadata: mergedMetadata(
                    [
                        "phase": "actual",
                        "sessionID": sessionID,
                        "turnIndex": "\(turnIndex)"
                    ]
                )
            )
        } else {
            actual = AgentCostCalculator.unavailable(
                usage: usage.costUsage,
                reason: "No default model was configured on the cost tracker.",
                metadata: mergedMetadata(
                    [
                        "phase": "actual",
                        "sessionID": sessionID,
                        "turnIndex": "\(turnIndex)"
                    ]
                )
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
            model: model,
            actual: actual,
            turns: [
                .init(
                    turnIndex: turnIndex,
                    requestModel: model,
                    actual: actual
                )
            ],
            metadata: mergedMetadata(
                [
                    "provider": provider
                ]
            )
        )
    }
}

private extension AgentCostTracker {
    func resolvedModel() -> String? {
        Self.normalized(
            defaultModel
        )
    }

    func mergedMetadata(
        _ values: [String: String]
    ) -> [String: String] {
        var result = metadata

        result.merge(
            values
        ) { _, new in
            new
        }

        if let region {
            result["region"] = region
        }

        return result
    }

    static func normalized(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? nil : trimmed
    }
}
