import Agentic
import Tokens

public extension AgentCostUsage {
    init(
        inputEstimate: TokenEstimate,
        reservedOutputTokens: Int = 0,
        requestCount: Int = 1,
        metadata: [String: String] = [:]
    ) {
        self.init(
            inputTokens: inputEstimate.estimatedTokens,
            outputTokens: reservedOutputTokens,
            requestCount: requestCount,
            metadata: metadata
        )
    }
}
