import Agentic
import AgenticExecution

public struct PendingApproval: Sendable, Codable, Hashable {
    public let toolCall: AgentToolCall
    public let preflight: ToolPreflight
    public let requirement: ApprovalRequirement

    public init(
        toolCall: AgentToolCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) {
        self.toolCall = toolCall
        self.preflight = preflight
        self.requirement = requirement
    }

    public var decision: ApprovalDecision {
        requirement.decision
    }
}
