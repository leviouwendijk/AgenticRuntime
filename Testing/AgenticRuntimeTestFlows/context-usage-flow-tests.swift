import Agentic
import AgenticRuntime
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runContextUsage() throws -> [TestDiagnostic] {
        let call = FunctionCall(
            id: "usage-call",
            name: "read_file",
            input: .object(["path": .string("Sources/Agentic/model/message.swift")])
        )
        let request = AgentRequest(
            messages: [
                .init(id: "sys", role: .system, content: .init(text: "You assist with Swift.")),
                .init(id: "u0", role: .user, content: .init(text: "Read the message type.")),
                .init(id: "a0", role: .assistant, content: .init(blocks: [.call(call)])),
                .init(id: "t0", role: .tool, content: .init(blocks: [
                    .result(.init(
                        call: call.reference,
                        output: .string(String(repeating: "public struct Message {}\n", count: 200))
                    )),
                ])),
            ],
            tools: [
                ToolDescriptor(
                    identifier: "read_file",
                    description: "Read a file.",
                    input: .object(["type": .string("object")])
                ),
            ]
        )

        let usage = Context.Usage(turn: 2, request: request)

        try Expect.equal(usage.turn, 2, "Usage keeps its turn")
        try Expect.true(usage.instructions > 0, "System text counts as instructions")
        try Expect.true(usage.conversation > 0, "User text counts as conversation")
        try Expect.true(usage.calls > 0, "Function calls are counted")
        try Expect.true(usage.tools > 0, "Function schemas are counted")
        try Expect.true(usage.results > usage.conversation, "Large results dominate the frame")
        try Expect.equal(
            usage.total,
            usage.instructions + usage.tools + usage.conversation
                + usage.calls + usage.results + usage.resources,
            "Total is the sum of its sections"
        )
        return [.field("usage", usage.summary)]
    }
}
