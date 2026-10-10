import Agentic
import IO
import AgenticRuntime
import Foundation
import TestFlows

private struct ContextAuditedFixtureInvoker: AgentModelInvoking {
    func buffered(_ invocation: AgentModelInvocation) async throws -> AgentModelInvocation.Result {
        let usage = AgentUsage(inputTokens: 23, outputTokens: 7, totalTokens: 30)
        let response = AgentResponse(
            message: Message(role: .assistant, text: "context audited fixture"),
            stopReason: .end_turn,
            usage: usage
        )
        return .init(response: response, route: .init(
            route: .init(
                purpose: invocation.selection.purpose,
                profile: .init(
                    identifier: "audit-fixture-profile",
                    gatewayIdentifier: "audit-fixture-gateway",
                    model: "audit-fixture-model",
                    purposes: [invocation.selection.purpose]
                )
            ), usage: usage
        ))
    }

    func stream(_ invocation: AgentModelInvocation) -> AsyncThrowingStream<AgentModelInvocation.Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await buffered(invocation)
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runContextInvocationAudit() async throws -> [TestDiagnostic] {
        let audit = Context.MemoryInferenceAuditStore()
        let wrapped = Context.AuditedModelInvoker(
            wrapping: ContextAuditedFixtureInvoker(), audit: audit
        )
        let request = AgentRequest(messages: [Message(role: .user, text: "Audit this inference")])
        let invocation = AgentModelInvocation(request: request, selection: .reviewer)
        let direct = try await wrapped.buffered(invocation)
        try Expect.equal(direct.response.usage?.inputTokens, 23,
            "Buffered invocation preserves provider usage")

        var streamed = false
        for try await item in wrapped.stream(invocation) {
            if case .completed(let result) = item {
                streamed = result.response.usage?.totalTokens == 30
            }
        }
        try Expect.equal(streamed, true, "Streaming completion is preserved")

        let events = await audit.snapshot()
        try Expect.equal(events.map(\.stage), [.submitted, .completed, .submitted, .completed],
            "Both delivery types record submission and completion")
        try Expect.equal(events[0].requestSHA256, events[1].requestSHA256,
            "One invocation has identical submitted and completed request fingerprints")
        try Expect.equal(events[0].invocationID, events[1].invocationID,
            "One invocation preserves a unique correlation identifier")
        try Expect.equal(events[0].invocationID == events[2].invocationID, false,
            "Repeated identical requests retain independent invocation identities")
        try Expect.equal(events[1].route?.route.profile.model, "audit-fixture-model",
            "Completed audit captures the routed model")
        try Expect.equal(events[3].providerUsage?.outputTokens, 7,
            "Completed streamed audit captures provider-reported usage")

        let frame = Context.Frame(
            workingSetID: "scope-A", items: [], skippedAllocationIDs: ["unneeded"],
            inputBudget: 500, estimatedInputTokens: 0
        )
        let prep = try Context.InferencePreparer.prepare(
            request: request, frame: frame, delivery: .supplement, maximumInputTokens: 500
        )
        let evidence = try Context.InferenceAuditFingerprint.prepared(prep)
        try await audit.record(evidence)
        try Expect.equal(evidence.workingSetID, "scope-A",
            "Prepared audit retains the working-set identity")
        try Expect.equal(evidence.frameSHA256?.hasPrefix("sha256:"), true,
            "Prepared audit has a content-derived frame fingerprint")

        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileSystem.default.remove(location) }
        let fileStore = try Context.FileInferenceAuditStore(fileURL: location)
        try await fileStore.record(evidence)
        let reopenedStore = try Context.FileInferenceAuditStore(fileURL: location)
        try await reopenedStore.record(evidence)
        let written = try String(contentsOf: location, encoding: .utf8)
        let lines = written.split(separator: "\n")
        try Expect.equal(lines.count, 2,
            "A reopened audit store appends rather than truncates")
        try Expect.equal(written.hasSuffix("\n"), true,
            "JSONL records remain newline terminated")
        try Expect.equal(lines.allSatisfy { line in
            (try? JSONDecoder().decode(
                Context.InferenceAuditEvent.self,
                from: Data(line.utf8)
            )) != nil
        }, true, "Every persisted audit line decodes independently")

        return [
            .message("Context inference auditing captures semantic requests, routes, usage and optional frame fingerprints"),
            .field("invocations", "2"),
            .field("events", String(events.count))
        ]
    }
}
