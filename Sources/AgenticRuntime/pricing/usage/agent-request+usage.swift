import Foundation
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

    /// Everything the request sends: function schemas, then each message's
    /// text, calls and results. Counting text alone undercounts tool-heavy turns.
    var estimatedPromptText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        func json(_ value: some Encodable) -> String {
            (try? encoder.encode(value)).map {
                String(decoding: $0, as: UTF8.self)
            } ?? ""
        }

        let schemas = tools.map(json)
        let conversation = messages.map { message in
            let content = message.content.blocks.map { block in
                if case .text(let text) = block {
                    return text
                }
                return json(block)
            }
            return "\(message.role.rawValue): " + content.joined(separator: "\n")
        }

        return (schemas + conversation).joined(
            separator: "\n\n"
        )
    }
}
