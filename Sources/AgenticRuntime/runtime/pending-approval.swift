import Agentic

public struct PendingApproval: Sendable, Codable, Hashable {
    public let toolCall: ToolCall
    public let preflight: ToolPreflight
    public let requirement: ApprovalRequirement
    public let preparedOperation: PreparedOperation.Envelope?

    public init(
        toolCall: ToolCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement,
        preparedOperation: PreparedOperation.Envelope? = nil
    ) {
        self.toolCall = toolCall
        self.preflight = preflight
        self.requirement = requirement
        self.preparedOperation = preparedOperation
    }

    public var decision: ApprovalDecision {
        requirement.decision
    }
}
