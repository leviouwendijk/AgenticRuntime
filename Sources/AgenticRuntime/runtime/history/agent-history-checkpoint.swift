import Agentic
import AgenticUsage
import Foundation

public enum AgentHistoryPhase: String, Sendable, Codable, Hashable, CaseIterable {
    case ready_for_model
    case receiving_model_response
    case processing_tool_calls
    case suspended
    case awaiting_approval
    case interrupted
    case failed
    case completed
}

public struct AgentHistoryCheckpoint: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let originalRequest: AgentRequest
    public var state: AgentLoopState
    public var events: [AgentRunEvent]
    public var phase: AgentHistoryPhase
    public var lastResponse: AgentResponse?
    public var partialResponse: AgentPartialResponse?
    public var toolBatch: AgentToolUseBatch?
    public var toolUses: [AgentToolUseRecord]
    public var suspension: AgentSuspension?
    public var pendingApproval: PendingApproval?
    public var failure: AgentRunFailure?
    public var costRecord: AgentCostRecord?
    public var exposedToolIdentifiers: [AgentToolIdentifier]?
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case originalRequest
        case state
        case events
        case phase
        case lastResponse
        case partialResponse
        case toolBatch
        case toolUses
        case suspension
        case pendingApproval
        case failure
        case costRecord
        case exposedToolIdentifiers
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decode(
            String.self,
            forKey: .id
        )
        originalRequest = try container.decode(
            AgentRequest.self,
            forKey: .originalRequest
        )
        state = try container.decode(
            AgentLoopState.self,
            forKey: .state
        )
        events = try container.decodeIfPresent(
            [AgentRunEvent].self,
            forKey: .events
        ) ?? []
        phase = try container.decode(
            AgentHistoryPhase.self,
            forKey: .phase
        )
        lastResponse = try container.decodeIfPresent(
            AgentResponse.self,
            forKey: .lastResponse
        )
        partialResponse = try container.decodeIfPresent(
            AgentPartialResponse.self,
            forKey: .partialResponse
        )
        toolBatch = try container.decodeIfPresent(
            AgentToolUseBatch.self,
            forKey: .toolBatch
        )
        toolUses = try container.decodeIfPresent(
            [AgentToolUseRecord].self,
            forKey: .toolUses
        ) ?? []
        suspension = try container.decodeIfPresent(
            AgentSuspension.self,
            forKey: .suspension
        )
        let decodedPendingApproval = try container.decodeIfPresent(
            PendingApproval.self,
            forKey: .pendingApproval
        )
        pendingApproval = decodedPendingApproval
            ?? suspension?.pendingApproval
        failure = try container.decodeIfPresent(
            AgentRunFailure.self,
            forKey: .failure
        )
        costRecord = try container.decodeIfPresent(
            AgentCostRecord.self,
            forKey: .costRecord
        )
        exposedToolIdentifiers = try container.decodeIfPresent(
            [AgentToolIdentifier].self,
            forKey: .exposedToolIdentifiers
        )
        updatedAt = try container.decode(
            Date.self,
            forKey: .updatedAt
        )
    }

    public init(
        id: String,
        originalRequest: AgentRequest,
        state: AgentLoopState,
        events: [AgentRunEvent] = [],
        phase: AgentHistoryPhase = .ready_for_model,
        lastResponse: AgentResponse? = nil,
        partialResponse: AgentPartialResponse? = nil,
        toolBatch: AgentToolUseBatch? = nil,
        toolUses: [AgentToolUseRecord] = [],
        suspension: AgentSuspension? = nil,
        pendingApproval: PendingApproval? = nil,
        failure: AgentRunFailure? = nil,
        costRecord: AgentCostRecord? = nil,
        exposedToolIdentifiers: [AgentToolIdentifier]? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.originalRequest = originalRequest
        self.state = state
        self.events = events
        self.phase = phase
        self.lastResponse = lastResponse
        self.partialResponse = partialResponse
        self.toolBatch = toolBatch
        self.toolUses = toolUses
        self.suspension = suspension
        self.pendingApproval = pendingApproval ?? suspension?.pendingApproval
        self.failure = failure
        self.costRecord = costRecord
        self.exposedToolIdentifiers = exposedToolIdentifiers
        self.updatedAt = updatedAt
    }
}

public extension AgentHistoryCheckpoint {
    var session: AgentSession {
        .init(
            id: id,
            messages: state.messages
        )
    }

    var resolvedSuspension: AgentSuspension? {
        if let suspension {
            return suspension
        }

        if let pendingApproval {
            return .approval(
                pendingApproval
            )
        }

        return nil
    }

    var pendingUserInput: PendingUserInput? {
        resolvedSuspension?.pendingUserInput
    }

    mutating func suspend(
        _ suspension: AgentSuspension
    ) {
        self.suspension = suspension
        self.pendingApproval = suspension.pendingApproval
        self.phase = .suspended
    }

    mutating func clearSuspension() {
        suspension = nil
        pendingApproval = nil

        if phase == .suspended || phase == .awaiting_approval {
            phase = .ready_for_model
        }
    }

    internal var resolvedToolUses: [AgentToolUseRecord] {
        var records = toolUses

        guard let toolBatch else {
            return records
        }

        for record in toolBatch.records {
            if let index = records.firstIndex(where: { existing in
                existing.id == record.id
            }) {
                records[index] = record
            } else {
                records.append(
                    record
                )
            }
        }

        return records
    }

    internal mutating func archiveToolUses(
        _ records: [AgentToolUseRecord]
    ) {
        for record in records {
            if let index = toolUses.firstIndex(where: { existing in
                existing.id == record.id
            }) {
                toolUses[index] = record
            } else {
                toolUses.append(
                    record
                )
            }
        }

        touch()
    }

    mutating func clearToolBatch() {
        toolBatch = nil
        touch()
    }

    mutating func touch(
        now: Date = Date()
    ) {
        updatedAt = now
    }
}
