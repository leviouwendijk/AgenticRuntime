import Agentic
import AgenticStandard
import Primitives

public extension FunctionCall {
    /// For a `call_capability` call, the capability it names: the runtime
    /// runs it as that capability's own call, under the same id, so it is
    /// shown by that name. Nil for any other call.
    var dispatchedIdentifier: String? {
        guard name == Standard.Tools.CallCapability.identifier.rawValue,
              case .object(let outer) = input,
              case .object(let arguments)? = outer["arguments"],
              case .string(let identifier)? = arguments["identifier"]
        else { return nil }
        return identifier
    }
}

public extension Sequence where Element == Message {
    /// The ids of the calls these messages made through `call_capability`.
    var dispatchedCallIDs: Set<String> {
        Set(flatMap(\.content.blocks).compactMap { block -> String? in
            guard case .call(let call) = block, call.dispatchedIdentifier != nil else { return nil }
            return call.id
        })
    }
}
