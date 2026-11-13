import Agentic
import AgenticRuntime
import Foundation
import IO
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runRunLog() async throws -> [TestDiagnostic] {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("run-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileSystem.default.remove(root) }

        let store = Run.Log.Store(storage: .init(root: root))
        let call = FunctionCall(
            id: "c1",
            name: "read_file",
            input: .object(["path": .string("README.md")])
        )
        let system = Message(id: "sys", role: .system, content: .init(text: "System"))
        let user = Message(id: "u0", role: .user, content: .init(text: "Read the readme."))
        let request = AgentRequest(messages: [system, user])
        let usage = Context.Usage(turn: 1, request: request)

        // First process: two turns sharing history, a call, its response,
        // a denial.
        do {
            let recorder = try store.open(session: "s1").recorder(run: "r1")
            try await recorder.record(.request(.init(request: request, usage: usage)))
            try await recorder.recordMessage(user)
            try await recorder.recordFunctionCall(call)
            try await recorder.record(.state(.init(
                kind: .tool_denied,
                iteration: 1,
                callID: call.id,
                toolName: call.name,
                summary: "denied by operator"
            )))
            try await recorder.recordToolResult(.init(
                call: call.reference,
                output: .string("denied"),
                isError: true
            ))
            try await recorder.record(.request(.init(request: request, usage: usage)))
        }

        // Second process: reopen, continue the sequence, then tear the tail.
        let log = try store.open(session: "s1")
        try await log.recorder(run: "r2").recordMessage(
            .init(id: "a0", role: .assistant, content: .init(text: "Done."))
        )
        let file = store.storage.logfile(sessionID: "s1")
        var torn = Destination(try SystemFileDestination(path: file.path, mode: .append))
        _ = try torn.write(Array(#"{"seq":99,"ti"#.utf8))
        _ = try torn.flush()

        let contents = try store.read(session: "s1")
        try Expect.equal(contents.header.session, "s1", "Header names the session")
        try Expect.equal(contents.entries.map(\.seq), Array(1...7), "Sequence continues across reopen")
        try Expect.equal(contents.entries.last?.run, "r2", "Entries name their run")

        guard case .request(let first) = contents.entries[0].body,
              case .request(let second) = contents.entries[5].body else {
            throw RunLogFixtureError.unexpectedBody
        }
        try Expect.equal(first.messages, second.messages, "Unchanged history is stored once")
        try Expect.equal(try store.request(first, session: "s1"), request, "Exact request is recoverable")

        guard case .state(let denial) = contents.entries[3].body else {
            throw RunLogFixtureError.unexpectedBody
        }
        try Expect.equal(denial.kind, .tool_denied, "Denials are recorded")

        guard case .response(let response) = contents.entries[4].body else {
            throw RunLogFixtureError.unexpectedBody
        }
        try Expect.true(response.isError, "Response keeps its error flag")
        let stored = try store.payload(response.digest, as: FunctionCall.Response.self, session: "s1")
        try Expect.equal(stored.output, .string("denied"), "Response body is recoverable")

        // Reopening after the torn write closes it off and keeps counting.
        try await store.open(session: "s1").append(.branch(.init(sessionID: "s1", branch: .init(parentSessionID: "s0"))), run: "r3")
        try Expect.equal(try store.read(session: "s1").entries.last?.seq, 8, "Torn tail is skipped")

        return [.field("entries", String(contents.entries.count))]
    }
}

private enum RunLogFixtureError: Error { case unexpectedBody }
