import Agentic
import AgenticRuntime
import Foundation
import Primitives
import Schema
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runToolObservationHistory() throws -> [TestDiagnostic] {
        let call = ToolCall(id: "history-observation", tool: "fixture", input: .null)
        var batch = AgentToolUseBatch(assistantMessageID: "assistant", toolCalls: [call])
        let observations: [ToolResultObservation] = [.init(kind: .detail, content: "exact evidence")]
        batch.mark(
            toolCallID: call.id,
            disposition: .executed,
            result: .init(call: .init(id: call.id, tool: call.tool), output: .null, isError: false),
            observations: observations
        )
        let decoded = try JSONDecoder().decode(AgentToolUseBatch.self, from: JSONEncoder().encode(batch))
        try Expect.equal(decoded.records.first?.observations, observations, "tool history persists observations")
        let record = try Expect.notNil(decoded.records.first, "history record exists")
        var legacy = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(record))
        legacy.removeValue(forKey: "observations")
        let restored = try JSONDecoder().decode(AgentToolUseRecord.self, from: JSONEncoder().encode(legacy))
        try Expect.equal(restored.observations, [], "older history remains readable")
        return [.field("observations", "retained in durable tool history")]
    }
}
