import Agentic
import AgenticStandard
import Foundation
import Primitives

/// A failed call's error, with what the model needs to make the next call
/// right: the error alone teaches little about a capability it has no
/// definition for.
struct CapabilityCallTeaching: LocalizedError, Sendable {
    let failure: String
    let guidance: String

    var errorDescription: String? {
        failure + " " + guidance
    }
}

extension AgentLoop {
    /// Adds guidance to a call's failure. A name nothing answers to says
    /// how to find a capability; an input error on a capability outside the
    /// tool definitions carries its contract, which the model otherwise has
    /// only from an inspection that may have left its context.
    func teaching(
        _ error: Error,
        for call: FunctionCall,
        checkpoint: AgentExecutor.Checkpoint
    ) async -> Error {
        guard let projection = checkpoint.lastAdvertisedCapabilities else { return error }
        let failure = localizedDescription(for: error)
        guard let target = projection.target(named: call.name) else {
            return CapabilityCallTeaching(
                failure: failure,
                guidance: "No capability named '\(call.name)' can be called here: find one with "
                    + "\(Standard.Tools.SearchCapabilities.identifier.rawValue) or "
                    + "\(Standard.Tools.ListCapabilities.identifier.rawValue), then read its contract with "
                    + "\(Standard.Tools.InspectCapability.identifier.rawValue)."
            )
        }
        guard projection.callable[call.name] != nil,
              Self.isInputError(error),
              let contract = try? await inventory.contract(for: target),
              let input = contract.input,
              let data = try? Self.contractEncoder.encode(input)
        else {
            return error
        }
        return CapabilityCallTeaching(
            failure: failure,
            guidance: "Its input, as \(Standard.Tools.InspectCapability.identifier.rawValue) gives it "
                + "(required fields in full; inspect it for the rest): "
                + String(decoding: data, as: UTF8.self)
        )
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
