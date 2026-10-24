import Agentic
import Foundation
import Primitives

/// A read-only projection of evidence already recorded by the runtime.
/// Structural containment here is limited to relationships the records establish:
/// run -> iteration -> tool call -> matching event, or program -> recorded step.
public struct AgentExecutionTrace: Sendable, Codable, Hashable {
    public let id: String
    public let tree: Tree<AgentExecutionTraceNode>

    public init(id: String, tree: Tree<AgentExecutionTraceNode>) {
        self.id = id
        self.tree = tree
    }
}

public struct AgentExecutionTraceNode: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: Sendable, Codable, Hashable {
        case run(AgentRunner.Phase)
        case iteration(Int)
        case tool(AgentToolUseDisposition?)
        case event(Run.Event.State.Kind)
        case program(ProgramExecutionOutcome)
        case program_step(ProgramStepKind)
        case unattributed_tools
        case invocation(AgentExecutionInvocation.Kind)
        case invocation_hierarchy
    }

    /// Unique occurrence identity in a projection; stable across resume.
    public let id: String
    public let kind: Kind
    /// Canonical record identifier, if one exists; does not imply a source symbol.
    public let reference_id: String?
    public let title: String
    public let detail: String?

    public init(id: String, kind: Kind, reference_id: String? = nil, title: String, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.reference_id = reference_id
        self.title = title
        self.detail = detail
    }
}

public enum AgentExecutionTraceError: Error, Sendable, Equatable {
    case duplicate_event(String)
    case duplicate_tool_call(String)
    case duplicate_program_step(Int)
}

public extension AgentExecutionTrace {
    /// Project the checkpoint evidence, without mutating or duplicating persistence.
    static func run(
        session_id: String,
        phase: AgentRunner.Phase,
        events: [Run.Event.State],
        tool_uses: [AgentToolUseRecord],
        invocations: [AgentExecutionInvocation] = []
    ) throws -> Self {
        let namespace = ["run", session_id]
        func key(_ components: [String]) -> String {
            trace_key(namespace + components)
        }

        var event_ids = Set<String>()
        var event_groups: [Int: [Run.Event.State]] = [:]
        for event in events {
            guard event_ids.insert(event.id).inserted else {
                throw AgentExecutionTraceError.duplicate_event(event.id)
            }
            event_groups[event.iteration, default: []].append(event)
        }

        var records: [String: AgentToolUseRecord] = [:]
        for record in tool_uses {
            guard records.updateValue(record, forKey: record.id) == nil else {
                throw AgentExecutionTraceError.duplicate_tool_call(record.id)
            }
        }

        // Latest observed iteration is where the durable disposition belongs.
        // Earlier occurrences retain their event history, but not a future status.
        var final_iteration: [String: Int] = [:]
        for event in events {
            if let tool_call_id = event.toolCallID {
                final_iteration[tool_call_id] = event.iteration
            }
        }
        let recorded_ids = Set(final_iteration.keys)
        let iterations: [Tree<AgentExecutionTraceNode>.Node] = event_groups.keys.sorted().map { iteration in
            let grouped = event_groups[iteration] ?? []
            var children: [Tree<AgentExecutionTraceNode>.Node] = []
            var tool_positions: [String: Int] = [:]
            for event in grouped {
                let event_node = Tree<AgentExecutionTraceNode>.Node(.init(
                    id: key(["event", event.id]),
                    kind: .event(event.kind),
                    reference_id: event.id,
                    title: event.kind.rawValue,
                    detail: event.summary
                ))
                guard let call_id = event.toolCallID else {
                    children.append(event_node)
                    continue
                }
                if let position = tool_positions[call_id] {
                    children[position].children.append(event_node)
                } else {
                    let record = final_iteration[call_id] == iteration ? records[call_id] : nil
                    let position = children.count
                    tool_positions[call_id] = position
                    children.append(.init(.init(
                        id: key(["iteration", String(iteration), "tool", call_id]),
                        kind: .tool(record?.disposition),
                        reference_id: call_id,
                        title: record?.toolCall.tool.rawValue ?? event.toolName ?? "tool call",
                        detail: record?.result.map { $0.isError ? "error" : "completed" }
                    ), children: [event_node]))
                }
            }
            return .init(.init(
                id: key(["iteration", String(iteration)]),
                kind: .iteration(iteration),
                title: "iteration \(iteration)"
            ), children: children)
        }

        var roots_children = iterations
        let unattributed = tool_uses.filter { !recorded_ids.contains($0.id) }
        if !unattributed.isEmpty {
            roots_children.append(.init(.init(
                id: key(["unattributed"]),
                kind: .unattributed_tools,
                title: "tool uses without iteration events"
            ), children: unattributed.map { record in
                .init(.init(
                    id: key(["unattributed", "tool", record.id]),
                    kind: .tool(record.disposition),
                    reference_id: record.id,
                    title: record.toolCall.tool.rawValue,
                    detail: nil
                ))
            }))
        }

        if !invocations.isEmpty {
            try AgentExecutionInvocationHistory.validate(invocations)
            let by_parent = Dictionary(grouping: invocations, by: \.parent_id)
            func project(_ span: AgentExecutionInvocation) -> Tree<AgentExecutionTraceNode>.Node {
                let children = (by_parent[span.id] ?? []).map(project)
                return .init(.init(
                    id: key(["invocation", span.id]),
                    kind: .invocation(span.kind),
                    reference_id: span.source_record_id ?? span.id,
                    title: span.target_id ?? span.kind.rawValue,
                    detail: span.state.rawValue
                ), children: children)
            }
            roots_children.insert(.init(.init(
                id: key(["invocations"]),
                kind: .invocation_hierarchy,
                title: "recorded invocation ancestry"
            ), children: (by_parent[nil] ?? []).map(project)), at: 0)
        }

        let root_id = key(["root"])
        return .init(id: root_id, tree: .init(roots: [.init(.init(
            id: root_id,
            kind: .run(phase),
            reference_id: session_id,
            title: "run \(session_id)",
            detail: phase.rawValue
        ), children: roots_children)]))
    }

    static func program(_ record: ProgramExecutionRecord) throws -> Self {
        let namespace = ["program", record.programIdentifier.rawValue,
                         record.sessionID ?? String(record.startedAt.timeIntervalSinceReferenceDate.bitPattern)]
        func key(_ components: [String]) -> String {
            trace_key(namespace + components)
        }
        var step_indices = Set<Int>()
        let steps: [Tree<AgentExecutionTraceNode>.Node] = try record.steps.map { step in
            guard step_indices.insert(step.index).inserted else {
                throw AgentExecutionTraceError.duplicate_program_step(step.index)
            }
            return .init(.init(
                id: key(["step", String(step.index)]),
                kind: .program_step(step.kind),
                reference_id: String(step.index),
                title: "step \(step.index)",
                detail: step.failure?.message
            ))
        }
        let root_id = key(["root"])
        return .init(id: root_id, tree: .init(roots: [.init(.init(
            id: root_id,
            kind: .program(record.outcome),
            reference_id: record.sessionID,
            title: "program \(record.programIdentifier.rawValue)",
            detail: record.failure?.message
        ), children: steps)]))
    }
}

private func trace_key(_ components: [String]) -> String {
    components.map { "\($0.utf8.count):\($0)" }.joined()
}

public extension AgentRunStateSnapshot {
    func execution_trace() throws -> AgentExecutionTrace {
        try .run(session_id: sessionID, phase: phase, events: events, tool_uses: toolUses, invocations: invocations ?? [])
    }
}

public extension AgentRunner.Result {
    func execution_trace() throws -> AgentExecutionTrace {
        try .run(session_id: sessionID, phase: phase, events: events, tool_uses: toolUses, invocations: invocations)
    }
}

public extension AgentRunner.Checkpoint {
    func execution_trace() throws -> AgentExecutionTrace {
        try .run(session_id: id, phase: phase, events: events, tool_uses: resolvedToolUses, invocations: invocations)
    }
}

public extension ProgramExecutionRecord {
    func execution_trace() throws -> AgentExecutionTrace {
        try AgentExecutionTrace.program(self)
    }
}
