import Agentic
import AgenticStandard
import Foundation
import Primitives

extension AgentLoop {
    /// Adds guidance to a call's failure. A name nothing answers to says
    /// how to find a capability; an input error on a capability outside the
    /// tool definitions carries its contract, which the model otherwise has
    /// only from an inspection that may have left its context.
    /// What the model needs, beyond the error itself, to make the next call
    /// right; nil when the error says enough. The error keeps its own
    /// structure and travels beside this.
    func guidance(
        for error: Error,
        call: FunctionCall,
        checkpoint: AgentExecutor.Checkpoint
    ) async -> String? {
        guard let projection = checkpoint.lastAdvertisedCapabilities else { return nil }
        guard let target = projection.target(named: call.name) else {
            return "No capability named '\(call.name)' can be called here: find one with "
                    + "\(Capabilities.Tools.Search.identifier.rawValue) or "
                    + "\(Capabilities.Tools.Search.identifier.rawValue), then read its contract with "
                    + "\(Capabilities.Tools.Inspect.identifier.rawValue)."
        }
        guard projection.callable[call.name] != nil,
              Self.isInputError(error),
              let contract = try? await inventory.contract(for: target),
              let input = contract.input,
              let data = try? Self.contractEncoder.encode(input)
        else {
            return nil
        }
        return "Its input, as \(Capabilities.Tools.Inspect.identifier.rawValue) gives it "
            + "(required fields in full; inspect it for the rest): "
            + String(decoding: data, as: UTF8.self)
    }

    private static let contractEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Errors about the shape of the call's input, which its contract
    /// answers; not failures of the capability itself.
    static func isInputError(
        _ error: Error
    ) -> Bool {
        switch error {
        case let failure as ToolExecution.Error:
            failure.failure.phase == .decode
        case ToolBindingError.invalidModelCall,
             RuntimeModelToolAuthorizationError.invalidArguments,
             is FunctionCall.MalformedArguments,
             is DecodingError:
            true
        default:
            false
        }
    }
}
