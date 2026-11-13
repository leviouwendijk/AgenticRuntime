import Agentic
import Macros
import Schema

public extension Run.Log.Entry {
    @JSONSchema
    enum Kind: String, Sendable, Codable, Hashable, CaseIterable {
        case state, observation, request, message, call, response, branch
    }

    var kind: Kind {
        switch body {
        case .state: .state
        case .observation: .observation
        case .request: .request
        case .message: .message
        case .call: .call
        case .response: .response
        case .branch: .branch
        }
    }

    /// The function call this entry is about, if any.
    var callID: String? {
        switch body {
        case .state(let state): state.callID
        case .observation(let observation): observation.origin?.call.id
        case .call(let call): call.call.id
        case .response(let response): response.call.id
        case .request, .message, .branch: nil
        }
    }

    /// One line describing the step, without loading any payload.
    var summary: String {
        switch body {
        case .state(let state):
            let subject = [state.toolName, state.callID]
                .compactMap { $0 }
                .joined(separator: " ")
            return [state.kind.rawValue, subject, state.summary]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        case .observation(let observation):
            let content = observation.content
                .split(whereSeparator: \.isNewline)
                .joined(separator: " ⏎ ")
            return [
                observation.kind.rawValue,
                observation.origin?.call.id ?? "",
                String(content.prefix(160)),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        case .request(let request):
            return "turn \(request.usage.turn) · \(request.usage.summary)"
        case .message(let stored):
            return "message \(stored.id)"
        case .call(let call):
            return "\(call.call.name) \(call.call.id)"
        case .response(let response):
            return "\(response.call.name) \(response.call.id)"
                + (response.isError ? " · error" : "")
        case .branch(let event):
            return "branch \(event.sessionID) from \(event.branch.parentSessionID)"
        }
    }
}
