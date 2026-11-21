import Agentic
import Foundation
import Primitives
import Schema

/// Abort the current provider response after a live capability mutation.
/// Successful invocations are journaled before crossing this boundary.
enum FunctionCallBoundaryError: Error, Sendable {
    case capabilities_changed
}

/// The parent must mirror this checkpoint rather than converting it to a
/// terminal model tool error. It contains no model-controlled authority.
struct RuntimeDelegatedChildSuspension: Error, Sendable {
    let call: FunctionCall
    let result: AgentExecutor.Result
}

/// A provider FunctionCall carries only a function name and JSON arguments.
/// Neither field may choose a semantic capability or an authorization origin.
struct CapabilityFunctionCallResolver: FunctionCallResolver, Sendable {
    let dispatcher: CapabilityDispatcher
    let projection: ModelCapabilityProjection
    let journal: AgentModelToolInvocationJournal?

    func resolve(_ call: FunctionCall) async throws -> FunctionCall.Response {
        let domains = if let inventory = dispatcher.inventory {
            await inventory.catalog().domains
        } else {
            dispatcher.services.tooling.catalog.domains
        }
        let call = projection.dispatched(call, domains: domains)
        let function = call.name
        guard let target = projection.target(named: function) else {
            // Reject names this request cannot call with the same typed
            // visibility error used by the governed Tool resolver. Later
            // changes cannot add authority to this captured projection.
            throw FunctionCallResolutionError.toolNotVisible(ToolIdentifier(call.name))
        }
        let invocation: CapabilityInvocation
        switch target {
        case .tool(let identifier):
            guard identifier == ToolIdentifier(call.name) else {
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

        case .agent(let identifier):
            let arguments = try semanticArguments(call.input)
            let binding = try await agentBinding(identifier)
            _ = try binding.verify(CapabilityCall(
                id: call.id,
                capability: .agent(identifier),
                input: arguments
            ))
            guard let parentSessionID = dispatcher.parentSessionID else {
                throw CapabilityInvocationError.agentRequiresDelegation(identifier)
            }
            let childID = "child:\(parentSessionID.utf8.count):\(parentSessionID):\(call.id.utf8.count):\(call.id)"
            var messages: [Message] = []
            if let instructions = binding.definition.instructions,
               !instructions.isEmpty {
                messages.append(Message(role: .system, text: instructions))
            }
            let context = dispatcher.services.tooling.services.contextEntries
            if let context {
                messages.append(context.message)
            }
            messages.append(Message(
                role: .user,
                text: String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
            ))
            var metadata = [
                "parent_agent_session_id": parentSessionID,
                "parent_agent_call_id": call.id
            ]
            if let context {
                metadata["context_always"] = context.ids.joined(separator: ",")
            }
            if case .object(let envelope) = call.input,
               let execution = envelope["execution"] {
                guard case .object(let fields) = execution,
                      fields.keys.allSatisfy({ $0 == "workspace_scope" }) else {
                    throw RuntimeModelToolAuthorizationError.invalidArguments
                }
                if let scope = fields["workspace_scope"] {
                    guard case .string(let path) = scope,
                          !path.isEmpty else {
                        throw RuntimeModelToolAuthorizationError.invalidArguments
                    }
                    metadata["worker_scope_path"] = path
                }
            }
            if let scope = metadata["worker_scope_path"] {
                messages.append(Message(
                    role: .system,
                    text: "Assigned workspace scope: \(scope). Only operate on that path or its descendants; approval is required for any expansion."
                ))
            } else {
                // Without a scope the child has no workspace at all; saying so
                // up front saves it failing tool by tool.
                messages.append(Message(
                    role: .system,
                    text: "No workspace scope was assigned, so file tools are unavailable. If the task needs files, report that the delegator must pass execution.workspace_scope."
                ))
            }
            invocation = .agent(
                identifier: identifier,
                request: AgentRequest(
                    messages: messages,
                    responseFormat: binding.contract.output == .string()
                        ? .text
                        : .jsonschema(binding.contract.output),
                    metadata: metadata
                ),
                sessionID: childID
            )
        }

        let before = await dispatcher.capabilityState.snapshot()
        let outcome: CapabilityInvocation.Outcome
        if case .agent(_, _, let childID) = invocation,
           let retained = await dispatcher.delegation?.latestResult(childID) {
            outcome = .agent(retained)
        } else {
            outcome = try await dispatcher.invoke(
                invocation,
                origin: .model(projection: projection, function: function)
            )
        }
        let response: FunctionCall.Response
        switch outcome {
        case .tool(let result):
            response = result
        case .program(let record):
            response = FunctionCall.Response(
                call: call.reference,
                output: try JSONCoding.default.value(record),
                isError: record.outcome != .succeeded
            )
        case .inference(let result):
            response = FunctionCall.Response(
                call: call.reference,
                output: try JSONDecoder().decode(JSONValue.self, from: result.output),
                isError: false
            )
        case .agent(let result):
            guard case .agent(_, let request, _) = invocation else {
                throw RuntimeModelToolAuthorizationError.invalidProjection
            }
            response = try await Self.agentResponse(
                result,
                for: call,
                responseFormat: request.responseFormat,
                delegation: dispatcher.delegation
            )
        }
        if case .tool = target {
            // Governed Tool results are retained through the dispatcher's
            // resolution observer, including their preflight/approval data.
        } else {
            await journal?.appendSemantic(call: call, result: response)
        }
        let after = await dispatcher.capabilityState.snapshot()
        guard before == after else {
            throw FunctionCallBoundaryError.capabilities_changed
        }
        return response
    }

    static func agentResponse(
        _ result: AgentExecutor.Result,
        for call: FunctionCall,
        responseFormat: AgentResponseFormat,
        delegation: AgentDelegation?
    ) async throws -> FunctionCall.Response {
        if result.suspension != nil {
            throw RuntimeDelegatedChildSuspension(call: call, result: result)
        }
        guard result.isCompleted,
              let message = result.response?.message else {
            return .init(
                call: call.reference,
                output: .object([
                    "child_session_id": .string(result.sessionID),
                    "phase": .string(result.phase.rawValue),
                    "failure": .string(result.failure?.message ?? "Child did not complete")
                ]),
                isError: true
            )
        }
        let output: JSONValue
        switch responseFormat {
        case .text:
            output = .string(message.content.text)
        case .jsonschema(let schema):
            let contract = AgentOutputContract(schema: schema)
            do {
                output = try contract.parse(message.content.text).value
            } catch {
                // One report-only repair, then the parent sees the failure.
                do {
                    guard let delegation else { throw error }
                    output = try await delegation.repairReport(result, contract: contract, failure: error).value
                } catch let repairFailure {
                    return .init(
                        call: call.reference,
                        output: .object([
                            "child_session_id": .string(result.sessionID),
                            "phase": .string(result.phase.rawValue),
                            "failure": .string("The child's report does not satisfy its output contract: \(error)"),
                            "repair": .string(String(describing: repairFailure)),
                            "answer": .string(message.content.text),
                        ]),
                        isError: true
                    )
                }
            }
        }
        return .init(
            call: call.reference,
            output: output,
            isError: false
        )
    }

    private func agentBinding(_ identifier: AgentIdentifier) async throws -> AgentBinding {
        if let inventory = dispatcher.inventory,
           let binding = await inventory.agentBinding(identifier) {
            return binding
        }
        if let runtime = dispatcher.runtime,
           let binding = runtime.installed.agentBinding(identifier) {
            return binding
        }
        throw CapabilityInvocationError.notInstalled(.agent(identifier))
    }

    private func semanticArguments(_ input: JSONValue) throws -> JSONValue {
        guard case .object(let fields) = input,
              let arguments = fields["arguments"] else {
            throw RuntimeModelToolAuthorizationError.invalidArguments
        }
        return arguments
    }
}
