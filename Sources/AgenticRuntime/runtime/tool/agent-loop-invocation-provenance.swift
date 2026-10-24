import Agentic
import Foundation

extension AgentLoop {
    /// The checkpoint is the sole owner of span state; result/trace layers read it.
    func begin_invocation(
        _ invocation: AgentExecutionInvocation,
        to checkpoint: inout AgentRunner.Checkpoint
    ) throws {
        guard !checkpoint.invocations.contains(where: { $0.id == invocation.id }) else {
            throw AgentExecutionInvocationError.duplicate_id(invocation.id)
        }
        if let parent = invocation.parent_id {
            guard parent != invocation.id else {
                throw AgentExecutionInvocationError.self_parent(invocation.id)
            }
            guard checkpoint.invocations.contains(where: { $0.id == parent }) else {
                throw AgentExecutionInvocationError.unknown_parent(
                    child: invocation.id, parent: parent
                )
            }
        }
        checkpoint.invocations.append(invocation)
    }

    func finish_invocation(
        id: String,
        state: AgentExecutionInvocation.State,
        to checkpoint: inout AgentRunner.Checkpoint
    ) throws {
        guard let index = checkpoint.invocations.firstIndex(where: { $0.id == id }) else {
            throw AgentExecutionInvocationError.unknown_invocation(id)
        }
        checkpoint.invocations[index].transition(to: state)
    }

    /// An established parent is a persisted model span, never the last event
    /// or a name-based guess. Legacy checkpoints fall back to the actual run.
    func ensure_run_invocation(in checkpoint: inout AgentRunner.Checkpoint) throws {
        let id = AgentExecutionInvocation.root_id(session_id: checkpoint.id)
        if !checkpoint.invocations.contains(where: { $0.id == id }) {
            try begin_invocation(
                .init(id: id, parent_id: nil, kind: .agent,
                      started_at: checkpoint.startedAt),
                to: &checkpoint
            )
        }
    }

    func begin_tool_invocation(
        call_id: String,
        tool_name: String,
        in checkpoint: inout AgentRunner.Checkpoint
    ) throws {
        let id = AgentExecutionInvocation.tool_id(session_id: checkpoint.id, call_id: call_id)
        guard !checkpoint.invocations.contains(where: { $0.id == id }) else { return }
        try ensure_run_invocation(in: &checkpoint)
        let kind: AgentExecutionInvocation.Kind
        if let projection = checkpoint.lastAdvertisedCapabilities,
           let target = projection.target(named: tool_name) {
            switch target {
            case .tool: kind = .tool
            case .program: kind = .program
            case .inference: kind = .inference
            case .agent: kind = .subagent
            }
        } else {
            kind = .tool
        }
        let candidate_parent = checkpoint.currentModelInvocationID
        let parent = candidate_parent.flatMap { candidate in
            checkpoint.invocations.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? AgentExecutionInvocation.root_id(session_id: checkpoint.id)
        try begin_invocation(
            .init(
                id: id, parent_id: parent, kind: kind,
                target_id: tool_name, source_record_id: call_id,
                iteration: checkpoint.state.iteration
            ), to: &checkpoint
        )
    }

    /// Only observed transitions are recorded. This neither synthesizes a
    /// nested program run nor claims an unrecorded subagent stack.
    func observe_invocation_event(
        _ event: Run.Event.State,
        in checkpoint: inout AgentRunner.Checkpoint
    ) throws {
        guard let call_id = event.toolCallID,
              let name = event.toolName else { return }
        switch event.kind {
        case .tool_preflight, .tool_approved, .tool_denied, .tool_skipped,
             .pending_approval, .pending_user_input, .pending_workspace_access,
             .tool_result, .tool_error:
            try begin_tool_invocation(call_id: call_id, tool_name: name, in: &checkpoint)
        default:
            return
        }
        let id = AgentExecutionInvocation.tool_id(session_id: checkpoint.id, call_id: call_id)
        switch event.kind {
        case .tool_result:
            try finish_invocation(id: id, state: .completed, to: &checkpoint)
        case .tool_error, .tool_denied:
            try finish_invocation(id: id, state: .failed, to: &checkpoint)
        case .tool_skipped:
            try finish_invocation(id: id, state: .interrupted, to: &checkpoint)
        case .pending_approval, .pending_user_input, .pending_workspace_access:
            try finish_invocation(id: id, state: .suspended, to: &checkpoint)
        case .tool_approved:
            try finish_invocation(id: id, state: .running, to: &checkpoint)
        default:
            break
        }
    }
}
