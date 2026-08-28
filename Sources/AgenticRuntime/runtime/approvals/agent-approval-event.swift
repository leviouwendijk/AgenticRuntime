import AgenticExecution
import Foundation

public struct AgentApprovalEvent: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, Hashable, CaseIterable {
        case tool_preflight
        case pending_approval
        case approval_decision
    }

    public let id: String
    public let sessionID: String
    public let runEventID: String?
    public let kind: Kind
    public let createdAt: Date
    public let iteration: Int
    public let toolCallID: String?
    public let toolName: String?
    public let decision: ApprovalDecision?
    public let summary: String

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        runEventID: String? = nil,
        kind: Kind,
        createdAt: Date = Date(),
        iteration: Int,
        toolCallID: String? = nil,
        toolName: String? = nil,
        decision: ApprovalDecision? = nil,
        summary: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.runEventID = runEventID
        self.kind = kind
        self.createdAt = createdAt
        self.iteration = iteration
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.decision = decision
        self.summary = summary
    }
}

public extension AgentApprovalEvent {
    init?(
        sessionID: String,
        runEvent: AgentRunEvent
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

        case .assistant_response,
             .compaction,
             .model_stream_started,
             .assistant_delta,
             .model_stream_tool_call,
             .model_stream_completed,
             .model_stream_interrupted,
             .model_stream_failed,
             .pending_user_input,
             .tool_result,
             .tool_error,
             .cost_projected,
             .cost_actual:
            return nil
        }

        self.init(
            sessionID: sessionID,
            runEventID: runEvent.id,
            kind: kind,
            iteration: runEvent.iteration,
            toolCallID: runEvent.toolCallID,
            toolName: runEvent.toolName,
            decision: decision,
            summary: runEvent.summary
        )
    }
}
