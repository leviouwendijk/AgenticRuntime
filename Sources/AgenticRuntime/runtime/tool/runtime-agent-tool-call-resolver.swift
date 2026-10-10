import Agentic
import Foundation
import Primitives

/// Abort the current provider response after a live capability mutation.
/// Successful invocations are journaled before crossing this boundary.
enum RuntimeToolCallBoundary: Error, Sendable {
    case capabilities_changed
}

/// A provider ToolCall carries only a function name and JSON arguments.
/// Neither field may choose a semantic capability or an authorization origin.
struct RuntimeModelCapabilityCallResolver: ToolCallResolver, Sendable {
    let dispatcher: CapabilityDispatcher
    let projection: ModelCapabilityProjection
    let journal: AgentModelToolInvocationJournal?

    func resolve(_ call: ToolCall) async throws -> ToolCall.Response {
        let function = call.tool.rawValue
        guard let target = projection.target(named: function) else {
            // Reject unadvertised names with the same typed visibility error
            // used by the governed Tool resolver. Later reveals cannot add
            // authority to this already-captured request projection.
            throw AgentToolCallResolutionError.toolNotVisible(call.tool)
        }
        let invocation: CapabilityInvocation
        switch target {
        case .tool(let identifier):
            guard identifier == call.tool else {
                throw RuntimeModelToolAuthorizationError.invalidProjection
            }
            invocation = .tool(call)

        case .program(let identifier):
            let arguments = try semanticArguments(call.input)
            let realization: JSONValue?
            if case .object(let values) = call.input {
                realization = values["execution"]
            } else {
                realization = nil
            }
            invocation = .program(
                identifier: identifier,
                input: arguments,
                realization: realization
            )

        case .inference(let identifier):
            invocation = .inference(
                identifier: identifier,
                input: try semanticArguments(call.input),
                realization: nil
            )

        case .agent:
            throw RuntimeModelToolAuthorizationError.invalidProjection
        }

        let before = await dispatcher.capabilityState.snapshot()
        let outcome = try await dispatcher.invoke(
            invocation,
            origin: .model(projection: projection, function: function)
        )
        let response: ToolCall.Response
        switch outcome {
        case .tool(let result):
            response = result
        case .program(let record):
            response = ToolCall.Response(
                call: call.reference,
                output: try JSONCoding.default.value(record),
                isError: record.outcome != .succeeded
            )
        case .inference(let result):
            response = ToolCall.Response(
                call: call.reference,
                output: try JSONDecoder().decode(JSONValue.self, from: result.output),
                isError: false
            )
        case .agent:
            throw RuntimeModelToolAuthorizationError.invalidProjection
        }
        if case .tool = target {
            // Governed Tool results are retained through the dispatcher's
            // resolution observer, including their preflight/approval data.
        } else {
            await journal?.appendSemantic(call: call, result: response)
        }
        let after = await dispatcher.capabilityState.snapshot()
        guard before == after else {
            throw RuntimeToolCallBoundary.capabilities_changed
        }
        return response
    }

    private func semanticArguments(_ input: JSONValue) throws -> JSONValue {
        guard case .object(let fields) = input,
              let arguments = fields["arguments"] else {
            throw RuntimeModelToolAuthorizationError.invalidArguments
        }
        return arguments
    }
}
