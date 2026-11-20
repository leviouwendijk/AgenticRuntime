import AgenticRuntime
import Foundation
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runInvocationTraceProjection() throws -> [TestDiagnostic] {
        let session = "model-only-run"
        let root = AgentExecutionInvocation(
            id: AgentExecutionInvocation.root_id(session_id: session),
            parent_id: nil, kind: .agent
        )
        var model = AgentExecutionInvocation(
            id: "model-one", parent_id: root.id, kind: .model, iteration: 1
        )
        model.transition(to: .completed)
        let trace = try AgentExecutionTrace.run(
            session_id: session, phase: .completed, events: [], tool_uses: [],
            invocations: [root, model]
        )
        let nodes = Array(trace.tree.walk())
        try Expect.true(nodes.contains(where: { $0.node.value.reference_id == model.id }),
                        "model-only execution is inspectable without tool events")
        let decoded = try JSONDecoder().decode(
            AgentExecutionTrace.self, from: JSONEncoder().encode(trace)
        )
        try Expect.equal(decoded, trace, "invocation projection round trips")
        do {
            _ = try AgentExecutionTrace.run(
                session_id: session, phase: .completed,
                events: [], tool_uses: [], invocations: [model]
            )
            throw InvocationTraceFixtureError.expected_rejection
        } catch AgentExecutionInvocationError.unknown_parent {
        }
        return [.field("trace", "model-only and persisted invocation spans")]
    }
}

private enum InvocationTraceFixtureError: Error {
    case expected_rejection
}
