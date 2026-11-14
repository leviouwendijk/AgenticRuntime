import Agentic
import AgenticStandard
import Tokens

extension AgentLoop {
    /// The response as the model reads it: whole, or, past the context
    /// policy's result budget, its beginning and where `read_result`
    /// continues. The full response is already in the session log, so
    /// nothing is lost, and the shortened form never changes afterwards,
    /// so the cached prefix stays valid.
    ///
    /// Applies only when the session is logged and `read_result` can be
    /// revealed; errors and `read_result`'s own pages are always whole.
    func budgeted(
        _ result: FunctionCall.Response
    ) async -> FunctionCall.Response {
        let reader = Standard.Tools.ReadResult.identifier
        guard let budget = configuration.contextPolicy.resultBudget,
              !result.isError,
              result.call.name != reader.rawValue,
              (try? tooling.services.require(Run.Log.self)) != nil
        else {
            return result
        }

        let options = TokenEstimationOptions.agenticContext
        func estimate(_ text: some StringProtocol) -> Int {
            TokenEstimator.estimate(String(text), options: options).estimatedTokens
        }

        let lines = ResultLines.lines(of: result.modelText)
        // Room for the closing note.
        let room = max(1, budget - 64)
        var used = 0
        var shown = 0
        for line in lines {
            let cost = estimate(line) + 1
            guard shown == 0 || used + cost <= room else {
                break
            }
            used += cost
            shown += 1
        }
        guard shown < lines.count else {
            return result
        }

        await capabilityState.reveal(AgentCapabilitySet(tools: [reader]))
        guard await capabilityState.snapshot().visible.tools.contains(reader) else {
            return result
        }

        let total = estimate(result.modelText)
        let note = "[Showing lines 1–\(shown) of \(lines.count) (≈\(used) of ≈\(total) tokens). "
            + "The full result is kept: read_result {\"call\": \"\(result.call.id)\", \"offset\": \(shown + 1)} continues.]"
        return result.rendered(
            lines[..<shown].joined(separator: "\n") + "\n" + note
        )
    }
}
