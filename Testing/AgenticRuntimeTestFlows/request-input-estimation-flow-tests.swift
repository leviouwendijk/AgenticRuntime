import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runRequestInputEstimation() throws -> [TestDiagnostic] {
        let call = FunctionCall(
            id: "estimate.read", name: "read_file",
            input: .object(["path": .string("Sources/Layout.swift")])
        )
        let rendered = FunctionCall.Response(
            call: call.reference,
            output: .object([
                "record": .string(String(repeating: "archived-only-source\n", count: 4_000)),
            ]),
            text: "Sources/Layout.swift:10 — the layout uses character wrapping."
        )
        let minimal = FunctionCall.Response(
            call: call.reference, output: .string(rendered.modelText), text: rendered.modelText
        )
        func request(_ result: FunctionCall.Response) -> AgentRequest {
            AgentRequest(messages: [
                .init(id: "estimate.user", role: .user, content: .init(text: "Review the layout.")),
                .init(id: "estimate.assistant", role: .assistant,
                      content: .init(blocks: [.call(call)])),
                .init(id: "estimate.tool", role: .tool, content: .init(blocks: [.result(result)])),
            ])
        }
        let archived = request(rendered)
        let visible = request(minimal)
        let estimate = archived.estimatedInputTokens().estimatedTokens
        try Expect.equal(
            estimate, visible.estimatedInputTokens().estimatedTokens,
            "Identical transmitted result text has identical estimates regardless of archive size"
        )
        try Expect.true(
            !archived.estimatedPromptText.contains("archived-only-source"),
            "Structured archival data does not become estimated prompt content"
        )
        let larger = request(.init(
            call: call.reference, output: .object([:]),
            text: String(repeating: "additional model-visible source line\n", count: 1_000)
        ))
        try Expect.true(
            larger.estimatedInputTokens().estimatedTokens > estimate,
            "Larger transmitted results still increase the estimate"
        )
        var constrained = archived
        constrained.responseFormat = .jsonschema(.object(
            description: String(repeating: "The answer must satisfy this field contract. ", count: 200)
        ))
        try Expect.true(
            constrained.estimatedInputTokens().estimatedTokens > estimate,
            "A structured output contract contributes to estimated input"
        )
        return [
            .field("rendered_input_tokens", String(estimate)),
            .field("schema_input_tokens", String(constrained.estimatedInputTokens().estimatedTokens)),
        ]
    }
}
