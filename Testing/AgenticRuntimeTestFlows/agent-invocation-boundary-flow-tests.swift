import AgenticRuntime
import Foundation
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runInvocationBoundaryContinuity() throws -> [TestDiagnostic] {
        let session = "invocation-continuity"
        let root = AgentExecutionInvocation(
            id: AgentExecutionInvocation.root_id(session_id: session),
            parent_id: nil, kind: .agent
        )
        var model = AgentExecutionInvocation(
            id: "model-1", parent_id: root.id, kind: .model, iteration: 1
        )
        model.transition(to: .completed)
        var tool = AgentExecutionInvocation(
            id: AgentExecutionInvocation.tool_id(session_id: session, call_id: "call-1"),
            parent_id: model.id, kind: .tool,
            target_id: "mutate_files", source_record_id: "call-1"
        )
        tool.transition(to: .suspended)
        let persisted = try JSONEncoder().encode([root, model, tool])
        var restored = try JSONDecoder().decode([AgentExecutionInvocation].self, from: persisted)
        try AgentExecutionInvocationHistory.validate(restored)
        try Expect.equal(restored[2].state, .suspended, "suspension is retained")
        restored[2].transition(to: .completed)
        try Expect.equal(restored[2].id, tool.id,
                         "a resumed tool keeps its logical call identity")
        try Expect.equal(restored[2].parent_id, model.id,
                         "resume retains the originating model span")
        return [.field("invocation", "resume preserves parent and identity")]
    }
}
