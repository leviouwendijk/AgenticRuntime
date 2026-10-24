import Agentic
import AgenticRuntime
import Difference
import Foundation
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runExecutionTraceDifference() throws -> [TestDiagnostic] {
        let call = ToolCall(id: "diff-tool", tool: "fixture", input: .null)
        let before = try AgentExecutionTrace.run(
            session_id: "diff-run", phase: .suspended,
            events: [.init(id: "existing", kind: .tool_preflight, iteration: 1,
                           toolCallID: call.id, toolName: "fixture", summary: "ready")],
            tool_uses: [.init(toolCall: call, disposition: .preflighted)]
        )
        let after = try AgentExecutionTrace.run(
            session_id: "diff-run", phase: .completed,
            events: [
                .init(id: "existing", kind: .tool_preflight, iteration: 1,
                      toolCallID: call.id, toolName: "fixture", summary: "ready"),
                .init(id: "new", kind: .tool_result, iteration: 1,
                      toolCallID: call.id, toolName: "fixture", summary: "executed")
            ],
            tool_uses: [.init(toolCall: call, disposition: .executed)]
        )
        let difference = try after.difference(from: before)
        let changed = Array(difference.tree.walk()).filter {
            $0.node.value.change != .unchanged
        }
        try Expect.equal(changed.count, 3,
                         "run phase and tool disposition modified; new result event added")
        let layout = try after.difference_layout(from: before)
        try Expect.true(!layout.lines.isEmpty, "semantic tree difference has layout")
        let unrelated = try AgentExecutionTrace.run(
            session_id: "other", phase: .completed, events: [], tool_uses: []
        )
        do {
            _ = try unrelated.difference(from: before)
            throw ExecutionTraceDiffFixtureFailure.missing_rejection
        } catch AgentExecutionTraceDifferenceError.different_roots {
            // A run is not compared to an unrelated run by accidental ID matching.
        }
        return [.field("changes", String(changed.count))]
    }
}

private enum ExecutionTraceDiffFixtureFailure: Error {
    case missing_rejection
}
