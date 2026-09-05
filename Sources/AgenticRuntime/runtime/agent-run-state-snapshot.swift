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
    public let phase: AgentHistoryPhase
    public let state: AgentLoopState
    public let events: [AgentRunEvent]
    public let lastResponse: AgentResponse?
    public let partialResponse: AgentPartialResponse?
    public let toolBatch: AgentToolUseBatch?
    public let toolUses: [AgentToolUseRecord]
    public let suspension: AgentSuspension?
    public let pendingApproval: PendingApproval?
    public let pendingUserInput: PendingUserInput?
    public let failure: AgentRunFailure?
    public let costRecord: AgentCostRecord?
    public let exposedToolIdentifiers: [AgentToolIdentifier]

    init(
        checkpoint: AgentHistoryCheckpoint
    ) {
        self.sessionID = checkpoint.id
        self.startedAt = checkpoint.startedAt
        self.updatedAt = checkpoint.updatedAt
        self.phase = checkpoint.phase
        self.state = checkpoint.state
        self.events = checkpoint.events
        self.lastResponse = checkpoint.lastResponse
        self.partialResponse = checkpoint.partialResponse
        self.toolBatch = checkpoint.toolBatch
        self.toolUses = checkpoint.resolvedToolUses
        self.suspension = checkpoint.resolvedSuspension
        self.pendingApproval = checkpoint.pendingApproval
        self.pendingUserInput = checkpoint.pendingUserInput
        self.failure = checkpoint.failure
        self.costRecord = checkpoint.costRecord
        self.exposedToolIdentifiers = checkpoint.exposedToolIdentifiers ?? []
    }
}
