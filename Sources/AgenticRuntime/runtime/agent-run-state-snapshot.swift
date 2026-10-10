import Agentic
import AgenticUsage
import Foundation

public struct AgentRunStateSnapshot:
    Sendable,
    Codable,
    Hashable
{
    public let sessionID: String
    public let startedAt: Date
    public let updatedAt: Date
    public let phase: AgentRunner.Phase
    public let state: AgentRunner.State
    public let runLimits: AgentRunLimits
    public let events: [Run.Event.State]
    public let lastResponse: AgentResponse?
    public let partialResponse: AgentPartialResponse?
    public let toolBatch: AgentToolUseBatch?
    public let toolUses: [AgentToolUseRecord]
    public let suspension: Run.Suspension?
    public let pendingApproval: PendingApproval?
    public let pendingUserInput: UserInputRequest?
    public let pendingRunLimit: AgentRunLimitExhaustion?
    public let failure: AgentRunFailure?
    public let costRecord: AgentCostRecord?
    public let capabilities: AgentCapabilityState.Snapshot

    init(
        checkpoint: AgentRunner.Checkpoint
    ) {
        self.sessionID = checkpoint.id
        self.startedAt = checkpoint.startedAt
        self.updatedAt = checkpoint.updatedAt
        self.phase = checkpoint.phase
        self.state = checkpoint.state
        self.runLimits = checkpoint.runLimits
        self.events = checkpoint.events
        self.lastResponse = checkpoint.lastResponse
        self.partialResponse = checkpoint.partialResponse
        self.toolBatch = checkpoint.toolBatch
        self.toolUses = checkpoint.resolvedToolUses
        self.suspension = checkpoint.resolvedSuspension
        self.pendingApproval = checkpoint.pendingApproval
        self.pendingUserInput = checkpoint.pendingUserInput
        self.pendingRunLimit = checkpoint.pendingRunLimit
        self.failure = checkpoint.failure
        self.costRecord = checkpoint.costRecord
        self.capabilities = checkpoint.capabilities
    }
}
