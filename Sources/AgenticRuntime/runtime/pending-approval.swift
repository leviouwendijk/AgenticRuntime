import Agentic

public struct PendingApproval: Sendable, Codable, Hashable {
    public let functionCall: FunctionCall
    public let preflight: ToolPreflight
    public let requirement: ApprovalRequirement
    public let preparedOperation: PreparedOperation.Envelope?

    public init(
        functionCall: FunctionCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement,
        preparedOperation: PreparedOperation.Envelope? = nil
    ) {
        self.functionCall = functionCall
        self.preflight = preflight
        self.requirement = requirement
        self.preparedOperation = preparedOperation
    }

    public var decision: ApprovalDecision {
        requirement.decision
    }
}
