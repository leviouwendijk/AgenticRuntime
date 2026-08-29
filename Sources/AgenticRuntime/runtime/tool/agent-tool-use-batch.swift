import Agentic
import AgenticExecution
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
    case suspended_for_user_input
    case skipped_after_mutation
    case skipped_after_denial
    case skipped_by_user
    case skipped_after_user_input
    case failed_preflight
    case failed_execution
}

public struct AgentToolUseRecord: Sendable, Codable, Hashable, Identifiable {
    public var toolCall: AgentToolCall
    public var disposition: AgentToolUseDisposition
    public var preflight: ToolPreflight?
    public var result: AgentToolResult?
    public var updatedAt: Date

    public init(
        toolCall: AgentToolCall,
        disposition: AgentToolUseDisposition = .pending,
        preflight: ToolPreflight? = nil,
        result: AgentToolResult? = nil,
        updatedAt: Date = Date()
    ) {
        self.toolCall = toolCall
        self.disposition = disposition
        self.preflight = preflight
        self.result = result
        self.updatedAt = updatedAt
    }

    public var id: String {
        toolCall.id
    }

    public var isTerminal: Bool {
        result != nil
    }

    public var isSuspended: Bool {
        switch disposition {
        case .suspended_for_approval,
             .suspended_for_user_input:
            return true

        case .pending,
             .preflighted,
             .executed,
             .skipped_after_mutation,
             .skipped_after_denial,
             .skipped_by_user,
             .skipped_after_user_input,
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
        toolCalls: [AgentToolCall],
        status: AgentToolUseStatus = .open,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.assistantMessageID = assistantMessageID
        self.status = status
        self.records = toolCalls.map {
            AgentToolUseRecord(
                toolCall: $0,
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
            toolCalls: response.message.toolUseCalls,
            status: status
        )
    }

    public init(
        assistantMessage: AgentMessage,
        status: AgentToolUseStatus = .open
    ) {
        self.init(
            assistantMessageID: assistantMessage.id,
            toolCalls: assistantMessage.toolUseCalls,
            status: status
        )
    }

    public var toolCalls: [AgentToolCall] {
        records.map(\.toolCall)
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
        for toolCallID: String
    ) -> AgentToolUseRecord? {
        records.first {
            $0.toolCall.id == toolCallID
        }
    }

    public func remaining(
        after toolCallID: String
    ) -> [AgentToolCall] {
        guard let index = records.firstIndex(where: { record in
            record.toolCall.id == toolCallID
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
            record.isTerminal ? nil : record.toolCall
        }
    }

    public mutating func mark(
        toolCallID: String,
        disposition: AgentToolUseDisposition,
        preflight: ToolPreflight? = nil,
        result: AgentToolResult? = nil,
        now: Date = Date()
    ) {
        guard let index = records.firstIndex(where: { record in
            record.toolCall.id == toolCallID
        }) else {
            return
        }

        records[index].disposition = disposition

        if let preflight {
            records[index].preflight = preflight
        }

        if let result {
            records[index].result = result
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

private extension AgentMessage {
    var toolUseCalls: [AgentToolCall] {
        content.blocks.compactMap { block in
            guard case .tool_call(let call) = block else {
                return nil
            }

            return call
        }
    }
}
