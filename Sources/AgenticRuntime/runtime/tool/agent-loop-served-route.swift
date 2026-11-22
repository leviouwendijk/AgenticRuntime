import Agentic
import AgenticStandard

/// What the route that served the run's last response can do; tools read
/// from it how to reach capabilities outside the definitions. Empty before
/// the first response and after a resume: the dispatcher, which every
/// gateway takes.
actor ServedRoute {
    private(set) var capabilities: Set<AgentModelCapability> = []

    func record(_ capabilities: some Sequence<AgentModelCapability>) {
        self.capabilities = Set(capabilities)
    }

    var callForm: UndeclaredCallForm {
        .init(byName: capabilities.contains(.undeclared_calls))
    }
}

extension AgentLoop {
    /// A reply carrying nothing, no text and no call, right after tool
    /// results would end the turn with nothing said. On a route that drops
    /// calls to tools outside the definitions it is most often such a call,
    /// gone on the way back. Asks once more per run, saying how to reach
    /// those, instead of completing silent.
    func recoverEmptyReply(
        _ response: AgentResponse,
        calls: [FunctionCall],
        route: AgentModelRouteRecord,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let messages = checkpoint.state.messages
        guard checkpoint.phase == .completed,
              calls.isEmpty,
              response.message.content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              messages.last?.id == response.message.id,
              messages.dropLast().last?.content.blocks.contains(where: { block in
                  if case .result = block { return true }
                  return false
              }) == true,
              !checkpoint.events.contains(where: { $0.kind == .empty_reply_recovered })
        else {
            return
        }
        // Some providers refuse an empty assistant turn in the history.
        checkpoint.state.messages.removeLast()
        let dispatcher = Capabilities.Tools.Call.identifier
        var note = "[Your last reply was empty. Continue the task"
        if !route.route.profile.capabilities.contains(.undeclared_calls),
           await capabilityState.snapshot().visible.tools.contains(dispatcher) {
            note += "; a capability that is not among your tools is called through \(dispatcher.rawValue), "
                + "with its identifier and its input"
        }
        note += ".]"
        checkpoint.state.messages.append(Message(role: .user, text: note))
        checkpoint.phase = .ready_for_model
        try await appendRunEvent(
            .init(
                kind: .empty_reply_recovered,
                iteration: checkpoint.state.iteration,
                messageID: response.message.id,
                summary: "an empty reply after tool results; asked once more"
            ),
            to: &checkpoint
        )
    }
}
