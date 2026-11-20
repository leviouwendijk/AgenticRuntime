import Agentic
import AgenticRuntime
import Foundation
import IO
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runCheckpointSnapshot() async throws -> [TestDiagnostic] {
        let transcript = (0..<40).map {
            Message(id: "m\($0)", role: $0.isMultiple(of: 2) ? .user : .assistant,
                    content: .init(text: String(repeating: "turn \($0) ", count: 50)))
        }
        let request = AgentRequest(
            messages: transcript,
            tools: [ToolDescriptor(identifier: "read_file", description: "Read a file.",
                                   input: .object(["type": .string("object")]))],
            metadata: ["origin": "test"]
        )
        let checkpoint = AgentExecutor.Checkpoint(
            id: "snapshot",
            request: request,
            state: .init(iteration: 3, messages: transcript),
            runLimits: .default
        )
        try Expect.true(checkpoint.request.messages.isEmpty, "The transcript is held once, in state")
        try Expect.true(checkpoint.request.tools.isEmpty, "Capability schemas are not snapshotted")
        try Expect.equal(checkpoint.request.metadata, ["origin": "test"], "Request settings are kept")

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("checkpoint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileSystem.default.remove(root) }
        let store = FileHistoryStore(sessionsdir: root)

        try await store.saveCheckpoint(checkpoint)
        var advanced = checkpoint
        advanced.state = .init(iteration: 4, messages: transcript)
        try await store.saveCheckpoint(advanced)

        let loaded = try await store.loadCheckpoint(sessionID: "snapshot")
        try Expect.equal(loaded?.state.iteration, 4, "A later save replaces the snapshot")
        try Expect.equal(loaded?.state.messages, transcript, "The transcript round-trips")
        try Expect.true(
            try await store.loadCheckpoint(sessionID: "absent") == nil,
            "A missing snapshot loads as nil"
        )

        let bytes = try JSONEncoder().encode(checkpoint).count
        let conversation = try JSONEncoder().encode(transcript).count
        try Expect.true(bytes < conversation * 3 / 2, "A snapshot is about one transcript in size")
        return [.field("bytes", String(bytes)), .field("transcript_bytes", String(conversation))]
    }
}
