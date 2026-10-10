import Agentic
import Tokens

public extension AgentResponse {
    func estimatedOutputCostUsage(
        options: TokenEstimationOptions = .conservative,
        requestCount: Int = 0
    ) -> AgentCostUsage {
        .init(
            outputTokens: estimatedOutputTokens(
                options: options
            ).estimatedTokens,
            requestCount: requestCount,
            metadata: [
                "source": "agent_response"
            ]
        )
    }

    func estimatedOutputTokens(
        options: TokenEstimationOptions = .conservative
    ) -> TokenEstimate {
        TokenEstimator.estimate(
            message.content.text,
            options: options,
            source: "agent_response"
        )
    }
}
