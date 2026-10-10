import Agentic
import Tokens

public extension AgentCostCalculator {
    static func project(
        inputEstimate: TokenEstimate,
        reservedOutputTokens: Int = 0,
        pricing: ModelPricingSnapshot,
        metadata: [String: String] = [:]
    ) -> AgentCostProjection {
        project(
            usage: .init(
                inputEstimate: inputEstimate,
                reservedOutputTokens: reservedOutputTokens,
                metadata: metadata
            ),
            pricing: pricing,
            metadata: metadata
        )
    }
}
