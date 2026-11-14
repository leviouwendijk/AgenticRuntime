import Agentic
import AgenticRuntime
import Primitives
import TestFlows

/// A delegator learns which of a worker's changes are staged rather than
/// on disk, so it reports them instead of retrying or checking the disk.
extension AgenticProgramRuntimeFlowTesting {
    static func runDelegatedStagedNote() throws -> [TestDiagnostic] {
        let mutate = FunctionCall(id: "m1", name: "mutate_files", input: .object([:]))
        let staged = AgentToolUseRecord(
            functionCall: mutate,
            disposition: .executed,
            result: .init(
                call: mutate.reference,
                output: .object([:]),
                projection: .init(
                    status: "staged",
                    summary: "1 updated",
                    facts: [.init(label: "control.swift", value: "updated · +2 · -1")]
                )
            )
        )
        func child(_ toolUses: [AgentToolUseRecord]) -> AgentExecutor.Result {
            .init(sessionID: "child", phase: .completed, response: nil, state: .init(), toolUses: toolUses)
        }
        let delegation = FunctionCall.Response(
            call: .init(id: "d1", name: "main_worker"),
            output: .string("Applied the edits.")
        )

        let noted = delegation.notingStaged(by: child([staged]))
        try Expect.true(
            noted.modelText.contains("Staged by the worker, not yet on disk: control.swift (updated · +2 · -1)"),
            "The delegator reads which changes are staged"
        )
        try Expect.equal(noted.output, delegation.output, "The worker's output is unchanged")
        try Expect.equal(
            delegation.notingStaged(by: child([])),
            delegation,
            "Without staged changes the response is unchanged"
        )
        return []
    }
}
