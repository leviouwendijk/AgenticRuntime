import Agentic
import AgenticStandard
import Primitives

public extension FunctionCall {
    /// For a `standard_tool_call_capability` call, the capability it names: the runtime
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
    /// The ids of the calls these messages made through `standard_tool_call_capability`.
    var dispatchedCallIDs: Set<String> {
        Set(flatMap(\.content.blocks).compactMap { block -> String? in
            guard case .call(let call) = block, call.dispatchedIdentifier != nil else { return nil }
            return call.id
        })
    }
}

extension AgentLoop {
    /// A tool among the definitions called through `standard_tool_call_capability` still
    /// runs, but its result says to call it by name: a few tokens once, and
    /// the model stops paying the wrapper on every call.
    func dispatchNoted(
        _ result: FunctionCall.Response,
        for call: FunctionCall,
        in checkpoint: AgentExecutor.Checkpoint
    ) -> FunctionCall.Response {
        guard checkpoint.lastAdvertisedCapabilities?.entries.contains(where: { $0.function.name == call.name }) == true,
              let asked = checkpoint.state.messages.last(where: { $0.role == .assistant }),
              asked.content.blocks.contains(where: { block in
                  guard case .call(let original) = block else { return false }
                  return original.id == call.id && original.dispatchedIdentifier != nil
              })
        else {
            return result
        }
        return result.rendered(
            result.modelText + "\n[`\(call.name)` is among your tools: call it by its own name, "
                + "not through \(Standard.Tools.CallCapability.identifier.rawValue).]"
        )
    }
}
