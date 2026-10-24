import Agentic
import AgenticRuntime
import Foundation
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runExecutionTraceProjection() throws -> [TestDiagnostic] {
        let call = ToolCall(id: "trace-call", tool: "fixture", input: .null)
        let record = AgentToolUseRecord(toolCall: call, disposition: .preflighted)
        let events: [Run.Event.State] = [
            .init(id: "trace-event-1", kind: .model_stream_started, iteration: 1,
                  summary: "model started"),
            .init(id: "trace-event-2", kind: .tool_preflight, iteration: 1,
                  toolCallID: call.id, toolName: "fixture", summary: "preflight"),
            .init(id: "trace-event-3", kind: .pending_approval, iteration: 1,
                  toolCallID: call.id, toolName: "fixture", summary: "awaiting review")
        ]
        let first = try AgentExecutionTrace.run(
            session_id: "trace-run", phase: .suspended, events: events,
            tool_uses: [record]
        )
        let second = try AgentExecutionTrace.run(
            session_id: "trace-run", phase: .suspended, events: events,
            tool_uses: [record]
        )
        try Expect.equal(first, second, "projection is deterministic across restore")
        try Expect.equal(Array(first.tree.walk()).count, 6,
                         "run/iteration/model event/tool/two tool events appear")
        let reloaded = try JSONDecoder().decode(
            AgentExecutionTrace.self, from: JSONEncoder().encode(first)
        )
        try Expect.equal(reloaded, first, "trace projection round-trips")
        do {
            _ = try AgentExecutionTrace.run(
                session_id: "trace-run", phase: .suspended,
                events: events + [events[0]], tool_uses: [record]
            )
            throw ExecutionTraceFixtureFailure.missing_rejection
        } catch AgentExecutionTraceError.duplicate_event(let id) {
            try Expect.equal(id, "trace-event-1", "duplicate event rejected")
        }
        let unrelated = AgentToolUseRecord(
            toolCall: ToolCall(id: "no-events", tool: "fixture", input: .null)
        )
        let orphan = try AgentExecutionTrace.run(
            session_id: "trace-run", phase: .suspended,
            events: [], tool_uses: [unrelated]
        )
        try Expect.equal(Array(orphan.tree.walk()).count, 3,
                         "tool without event is not assigned an invented iteration")
        return [.field("projection", "run, iteration, tool, events and unattributed evidence")]
    }
}

private enum ExecutionTraceFixtureFailure: Error {
    case missing_rejection
}
