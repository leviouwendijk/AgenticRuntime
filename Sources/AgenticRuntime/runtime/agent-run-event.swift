import Foundation

public struct AgentRunEvent: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, Hashable, CaseIterable {
        case assistant_response
        case compaction
        case model_stream_started
        case assistant_delta
        case model_stream_tool_call
        case model_stream_completed
        case model_stream_interrupted
        case model_stream_failed
        case tool_preflight
        case tool_approved
        case tool_denied
        case pending_approval
        case pending_user_input
        case tool_result
        case tool_error
        case cost_projected
        case cost_actual
    }

    public let id: String
    public let kind: Kind
    public let iteration: Int
    public let messageID: String?
    public let toolCallID: String?
    public let toolName: String?
    public let summary: String

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        iteration: Int,
        messageID: String? = nil,
        toolCallID: String? = nil,
        toolName: String? = nil,
        summary: String
    ) {
        self.id = id
        self.kind = kind
        self.iteration = iteration
        self.messageID = messageID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.summary = summary
    }
}
