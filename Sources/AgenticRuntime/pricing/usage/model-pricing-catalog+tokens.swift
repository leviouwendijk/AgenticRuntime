import Agentic
import Foundation
import Tokens

public extension ModelPricingCatalog {
    func projectCost(
        provider: String,
        model: String,
        region: String? = nil,
        inputEstimate: TokenEstimate,
        reservedOutputTokens: Int = 0,
        metadata: [String: String] = [:]
    ) -> AgentCostProjection {
        do {
            let pricing = try pricing(
                for: .init(
                    provider: provider,
                    model: model,
                    region: region
                )
            )

            return AgentCostCalculator.project(
                inputEstimate: inputEstimate,
                reservedOutputTokens: reservedOutputTokens,
                pricing: pricing,
                metadata: metadata
            )
        } catch {
            return AgentCostCalculator.unavailable(
                usage: .init(
                    inputEstimate: inputEstimate,
                    reservedOutputTokens: reservedOutputTokens,
                    metadata: metadata
                ),
                reason: error.localizedDescription,
                metadata: metadata
            )
        }
    }
}
