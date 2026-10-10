import Agentic
import Tokens

public extension AgentRequest {
    func estimatedInputCostUsage(
        options: TokenEstimationOptions = .agenticContext,
        reservedOutputTokens: Int = 0,
        requestCount: Int = 1
    ) -> AgentCostUsage {
        .init(
            inputEstimate: estimatedInputTokens(
                options: options
            ),
            reservedOutputTokens: reservedOutputTokens,
            requestCount: requestCount,
            metadata: [
                "source": "agent_request"
            ]
        )
    }

    func estimatedInputTokens(
        options: TokenEstimationOptions = .agenticContext
    ) -> TokenEstimate {
        TokenEstimator.estimate(
            estimatedPromptText,
            options: options,
            source: "agent_request"
        )
    }

    var estimatedPromptText: String {
        messages.map { message in
            "\(message.role.rawValue): \(message.content.text)"
        }.joined(
            separator: "\n\n"
        )
    }
}
