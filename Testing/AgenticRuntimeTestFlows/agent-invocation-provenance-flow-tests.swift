import AgenticRuntime
import Foundation
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runInvocationProvenanceContract() throws -> [TestDiagnostic] {
        let root = AgentExecutionInvocation(
            id: AgentExecutionInvocation.root_id(session_id: "provenance-run"),
            parent_id: nil, kind: .agent
        )
        let child = AgentExecutionInvocation(
            id: "model-1", parent_id: root.id, kind: .model,
            iteration: 1
        )
        try AgentExecutionInvocationHistory.validate([root, child])
        let copy = try JSONDecoder().decode(
            [AgentExecutionInvocation].self,
            from: JSONEncoder().encode([root, child])
        )
        try Expect.equal(copy, [root, child], "invocation evidence is serializable")
        do {
            try AgentExecutionInvocationHistory.validate([child])
            throw InvocationProvenanceFixtureError.expected_rejection
        } catch AgentExecutionInvocationError.unknown_parent {
            // An absent parent is not reconstructed by proximity or name.
        }
        do {
            try AgentExecutionInvocationHistory.validate([root, root])
            throw InvocationProvenanceFixtureError.expected_rejection
        } catch AgentExecutionInvocationError.duplicate_id {
        }
        return [.field("provenance", "identity, ancestry and decoding")]
    }
}

private enum InvocationProvenanceFixtureError: Error {
    case expected_rejection
}
