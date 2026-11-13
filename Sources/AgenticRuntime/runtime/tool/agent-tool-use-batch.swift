import Agentic
import Foundation

public enum AgentToolUseStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case open
    case suspended
    case completed
    case failed
}

public enum AgentToolUseDisposition: String, Sendable, Codable, Hashable, CaseIterable {
    case pending
    case preflighted
    case executed
    case suspended_for_approval
    case suspended_for_delegation
    case suspended_for_user_input
    case suspended_for_workspace_access
    case skipped_after_mutation
    case skipped_after_denial
    case skipped_by_user
    case skipped_after_user_input
    case skipped_after_workspace_access
    case failed_preflight
    case failed_execution
}

public struct AgentToolUseRecord: Sendable, Codable, Hashable, Identifiable {
    public var functionCall: FunctionCall
    public var disposition: AgentToolUseDisposition
    public var preflight: ToolPreflight?
    public var result: FunctionCall.Response?
    public var recovery: Recovery.Record?
    public var observations: [ToolResultObservation]
    public var updatedAt: Date

    public init(
        functionCall: FunctionCall,
        disposition: AgentToolUseDisposition = .pending,
        preflight: ToolPreflight? = nil,
        result: FunctionCall.Response? = nil,
        recovery: Recovery.Record? = nil,
        observations: [ToolResultObservation] = [],
        updatedAt: Date = Date()
    ) {
        self.functionCall = functionCall
        self.disposition = disposition
        self.preflight = preflight
        self.result = result
        self.recovery = recovery
        self.observations = observations
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case functionCall, disposition, preflight, result, recovery, observations, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            functionCall: try values.decode(FunctionCall.self, forKey: .functionCall),
            disposition: try values.decode(AgentToolUseDisposition.self, forKey: .disposition),
            preflight: try values.decodeIfPresent(ToolPreflight.self, forKey: .preflight),
            result: try values.decodeIfPresent(FunctionCall.Response.self, forKey: .result),
            recovery: try values.decodeIfPresent(Recovery.Record.self, forKey: .recovery),
            observations: try values.decodeIfPresent([ToolResultObservation].self, forKey: .observations) ?? [],
            updatedAt: try values.decode(Date.self, forKey: .updatedAt)
        )
    }

    public var id: String {
        functionCall.id
    }

    public var isTerminal: Bool {
        result != nil
    }

    public var isSuspended: Bool {
        switch disposition {
        case .suspended_for_approval,
             .suspended_for_delegation,
             .suspended_for_user_input,
             .suspended_for_workspace_access:
            return true

        case .pending,
             .preflighted,
             .executed,
             .skipped_after_mutation,
             .skipped_after_denial,
             .skipped_by_user,
             .skipped_after_user_input,
             .skipped_after_workspace_access,
             .failed_preflight,
             .failed_execution:
            return false
        }
    }
}

public struct AgentToolUseBatch: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var assistantMessageID: String
    public var status: AgentToolUseStatus
    public var records: [AgentToolUseRecord]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        assistantMessageID: String,
        functionCalls: [FunctionCall],
        status: AgentToolUseStatus = .open,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.assistantMessageID = assistantMessageID
        self.status = status
        self.records = functionCalls.map {
            AgentToolUseRecord(
                functionCall: $0,
                updatedAt: updatedAt
            )
        }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(
        response: AgentResponse,
        status: AgentToolUseStatus = .open
    ) {
        self.init(
            assistantMessageID: response.message.id,
            functionCalls: response.message.toolUseCalls,
            status: status
        )
    }

    public init(
        assistantMessage: Message,
        status: AgentToolUseStatus = .open
    ) {
        self.init(
            assistantMessageID: assistantMessage.id,
            functionCalls: assistantMessage.toolUseCalls,
            status: status
        )
    }

    public var functionCalls: [FunctionCall] {
        records.map(\.functionCall)
    }

    public var pendingRecords: [AgentToolUseRecord] {
        records.filter {
            !$0.isTerminal
        }
    }

    public var hasPendingRecords: Bool {
        !pendingRecords.isEmpty
    }

    public var isComplete: Bool {
        !records.isEmpty && records.allSatisfy(\.isTerminal)
    }

    public func record(
        for callID: String
    ) -> AgentToolUseRecord? {
        records.first {
            $0.functionCall.id == callID
        }
    }

    public func remaining(
        after callID: String
    ) -> [FunctionCall] {
        guard let index = records.firstIndex(where: { record in
            record.functionCall.id == callID
        }) else {
            return []
        }

        let nextIndex = records.index(
            after: index
        )

        guard nextIndex < records.endIndex else {
            return []
        }

        return records[nextIndex...].compactMap { record in
            record.isTerminal ? nil : record.functionCall
        }
    }

    public mutating func mark(
        callID: String,
        disposition: AgentToolUseDisposition,
        preflight: ToolPreflight? = nil,
        result: FunctionCall.Response? = nil,
        recovery: Recovery.Record? = nil,
        observations: [ToolResultObservation] = [],
        now: Date = Date()
    ) {
        guard let index = records.firstIndex(where: { record in
            record.functionCall.id == callID
        }) else {
            return
        }

        records[index].disposition = disposition

        if let preflight {
            records[index].preflight = preflight
        }

        if let result {
            records[index].result = result
            records[index].observations = observations
        }

        if let recovery {
            records[index].recovery = recovery
        }

        records[index].updatedAt = now
        updatedAt = now
    }

    public mutating func completeIfTerminal(
        now: Date = Date()
    ) {
        guard isComplete else {
            return
        }

        status = .completed
        updatedAt = now
    }

    public mutating func suspend(
        now: Date = Date()
    ) {
        status = .suspended
        updatedAt = now
    }

    public mutating func failIfOpen(
        now: Date = Date()
    ) {
        guard status == .open || status == .suspended else {
            return
        }

        status = .failed
        updatedAt = now
    }
}

private extension Message {
    var toolUseCalls: [FunctionCall] {
        content.blocks.compactMap { block in
            guard case .call(let call) = block else {
                return nil
            }

            return call
        }
    }
}
