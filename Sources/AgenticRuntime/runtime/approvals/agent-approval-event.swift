import Agentic
import AgenticSessions
import Foundation
import Macros
import Schema

public extension Sessions.ApprovalEvent {
    init?(
        sessionID: String,
        runEvent: Run.Event.State
    ) {
        let kind: Kind
        let decision: ApprovalDecision?

        switch runEvent.kind {
        case .tool_preflight:
            kind = .tool_preflight
            decision = nil

        case .pending_approval:
            kind = .pending_approval
            decision = .needshuman

        case .tool_approved:
            kind = .approval_decision
            decision = .approved

        case .tool_denied:
            kind = .approval_decision
            decision = .denied

        case .tool_skipped:
            kind = .approval_decision
            decision = .skipped

        case .assistant_response,
             .run_failed,
             .run_limit_reached,
             .run_limit_continued,
             .run_limit_stopped,
             .run_interrupted,
             .compaction,
             .context_usage,
             .model_stream_started,
             .assistant_delta,
             .model_stream_tool_call,
             .model_stream_completed,
             .model_stream_interrupted,
             .model_stream_failed,
             .pending_user_input,
             .pending_workspace_access,
             .tool_result,
             .tool_error,
             .cost_projected,
             .cost_actual,
             .mutation_staged,
             .mutation_published,
             .mutation_withdrawn,
             .operator_command,
             .workspace_changed,
             .output_repaired,
             .input_applied,
             .context_changed,
             .context_pressure:
            return nil
        }

        self.init(
            sessionID: sessionID,
            runEventID: runEvent.id,
            kind: kind,
            iteration: runEvent.iteration,
            callID: runEvent.callID,
            toolName: runEvent.toolName,
            decision: decision,
            summary: runEvent.summary
        )
    }
}
