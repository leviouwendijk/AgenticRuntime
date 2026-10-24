import Foundation

/// An observed invocation, not an inferred edge in a call graph.
/// Parent IDs are assigned at the execution boundary. Missing parents are
/// rejected by the validated projection rather than matched heuristically.
public struct AgentExecutionInvocation: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, Hashable, CaseIterable {
        case agent
        case model
        case tool
        case program
        case inference
        case subagent
    }

    public enum State: String, Sendable, Codable, Hashable, CaseIterable {
        case running
        case completed
        case failed
        case suspended
        case interrupted
    }

    public let id: String
    public let parent_id: String?
    public let kind: Kind
    public let target_id: String?
    public let source_record_id: String?
    public let iteration: Int?
    public let started_at: Date
    public private(set) var state: State
    public private(set) var finished_at: Date?

    public init(
        id: String,
        parent_id: String?,
        kind: Kind,
        target_id: String? = nil,
        source_record_id: String? = nil,
        iteration: Int? = nil,
        started_at: Date = Date(),
        state: State = .running,
        finished_at: Date? = nil
    ) {
        self.id = id
        self.parent_id = parent_id
        self.kind = kind
        self.target_id = target_id
        self.source_record_id = source_record_id
        self.iteration = iteration
        self.started_at = started_at
        self.state = state
        self.finished_at = finished_at
    }

    /// This canonical root identity survives save/restore and does not rely on
    /// a generated event or a source location.
    public static func root_id(session_id: String) -> String {
        "run:\(session_id.utf8.count):\(session_id)"
    }

    /// A model tool-call ID identifies one logical tool invocation, including
    /// its continuation after approval suspension.
    public static func tool_id(session_id: String, call_id: String) -> String {
        "tool:\(session_id.utf8.count):\(session_id):\(call_id.utf8.count):\(call_id)"
    }

    public mutating func transition(to next: State, at date: Date = Date()) {
        state = next
        finished_at = next == .running || next == .suspended ? nil : date
    }
}

public enum AgentExecutionInvocationError: Error, Sendable, Equatable {
    case empty_id
    case duplicate_id(String)
    case self_parent(String)
    case unknown_parent(child: String, parent: String)
    case cyclic_parent(String)
    case unknown_invocation(String)
}

public enum AgentExecutionInvocationHistory {
    /// Unlike a display-only projector, validation preserves the declared
    /// parent relationship and rejects references that were not recorded.
    public static func validate(_ records: [AgentExecutionInvocation]) throws {
        var ids = Set<String>()
        var parents: [String: String] = [:]
        for record in records {
            guard !record.id.isEmpty else { throw AgentExecutionInvocationError.empty_id }
            guard ids.insert(record.id).inserted else {
                throw AgentExecutionInvocationError.duplicate_id(record.id)
            }
            if let parent = record.parent_id {
                guard parent != record.id else {
                    throw AgentExecutionInvocationError.self_parent(record.id)
                }
                parents[record.id] = parent
            }
        }
        for (id, parent) in parents {
            guard ids.contains(parent) else {
                throw AgentExecutionInvocationError.unknown_parent(child: id, parent: parent)
            }
        }
        for id in ids {
            var seen = Set<String>()
            var cursor: String? = id
            while let next = cursor {
                guard seen.insert(next).inserted else {
                    throw AgentExecutionInvocationError.cyclic_parent(id)
                }
                cursor = parents[next]
            }
        }
    }
}
