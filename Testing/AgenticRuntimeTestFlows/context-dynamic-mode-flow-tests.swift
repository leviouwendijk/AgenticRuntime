import Agentic
import AgenticRuntime
import Foundation
import TestFlows

private struct DynamicFixtureResolver: Context.RecordResolving {
    func resolve(_ pointer: Context.Pointer) async throws -> Context.Resolved {
        .init(
            pointer: .init(
                source: pointer.source,
                record: pointer.record,
                selection: pointer.selection,
                revision: .recorded("fixture-v1")
            ),
            messages: [.init(
                id: "dynamic.evidence",
                role: .assistant,
                content: .init(text: "Rehydrated earlier source evidence")
            )]
        )
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runContextDynamicMode() async throws -> [TestDiagnostic] {
        let policy = Context.Policy(
            preferredInputTokens: 1_000,
            maximumInputTokens: 5_000,
            reservedOutputTokens: 200,
            history: .init(maximumTurns: 2, maximumTokens: 2_000)
        )
        let allocator = try Context.Allocator(policy: policy)
        try await allocator.createWorkingSet(id: "session-dynamic")

        let system = Message(id: "sys", role: .system, content: .init(text: "Preserve constraints"))
        let earlier = Message(id: "old", role: .user, content: .init(text: "Old task"))
        let intermediate = Message(id: "middle", role: .user, content: .init(text: "Intermediate task"))
        let current = Message(id: "current", role: .user, content: .init(text: "Current task"))
        let canonical = AgentRequest(messages: [system, earlier, intermediate, current])
        let first = try await allocator.prepareDynamic(
            request: canonical,
            for: "session-dynamic",
            using: DynamicFixtureResolver(),
            modelContextLimit: 6_000
        )
        try Expect.equal(first.request.messages.map(\.id), ["sys", "middle", "current"],
            "Dynamic mode retains protected system messages and two complete recent turns")
        try Expect.equal(first.history.omitted.map(\.messageID), ["old"],
            "Evicted history is identified by stable checkpoint position and message ID")
        try Expect.equal(canonical.messages.count, 4,
            "Dynamic preparation never rewrites canonical history")

        try await allocator.apply([
            .allocate(.init(id: "old-evidence", pointer: .init(
                source: "fixture", record: "previous-turn", revision: .recorded("fixture-v1")
            ), required: true))
        ], to: "session-dynamic")
        let second = try await allocator.prepareDynamic(
            request: canonical,
            for: "session-dynamic",
            using: DynamicFixtureResolver(),
            modelContextLimit: 6_000
        )
        try Expect.equal(second.request.messages.map(\.id),
            ["sys", "dynamic.evidence", "middle", "current"],
            "Explicitly referenced historical evidence can be rehydrated on demand")
        try Expect.equal(second.frame.items.count, 1,
            "Evidence allocation and history tail share the allocator's bounded frame")

        let whole = Context.Frame(
            workingSetID: "session-dynamic", items: [],
            skippedAllocationIDs: [], inputBudget: 5_000, estimatedInputTokens: 0
        )
        let accumulating = try Context.InferencePreparer.prepare(
            request: canonical, frame: whole, delivery: .supplement,
            maximumInputTokens: 5_000
        )
        try Expect.equal(accumulating.request.messages.map(\.id),
            ["sys", "old", "middle", "current"],
            "Accumulating mode preserves append-only model-facing history")

        let oversizedPolicy = Context.Policy(
            preferredInputTokens: 1_000,
            maximumInputTokens: 5_000,
            reservedOutputTokens: 200,
            history: .init(maximumTurns: 1, maximumTokens: 350)
        )
        let oversizedAllocator = try Context.Allocator(policy: oversizedPolicy)
        try await oversizedAllocator.createWorkingSet(id: "large-output")
        let readCall = ToolCall(id: "large-read", tool: "fixture.read", input: .null)
        let hugeResult = Message(
            id: "large-result", role: .tool,
            content: .init(blocks: [.tool_result(.init(
                call: .init(id: "large-read", tool: "fixture.read"),
                output: .string(String(repeating: "expanded-evidence ", count: 2_000))
            ))])
        )
        let largeRequest = AgentRequest(messages: [
            system, current,
            .init(id: "large-call", role: .assistant, content: .init(blocks: [.tool_call(readCall)])),
            hugeResult
        ])
        let reduced = try await oversizedAllocator.prepareDynamic(
            request: largeRequest, for: "large-output",
            using: DynamicFixtureResolver(), modelContextLimit: 6_000
        )
        try Expect.equal(reduced.request.messages.map(\.id), ["sys", "current"],
            "Large completed tool exchanges can leave the active frame intact")
        try Expect.equal(reduced.history.omitted.map(\.messageID), ["large-call", "large-result"],
            "Evicted tool call and result remain referenced together")

        let checkpoint = AgentRunner.Checkpoint(
            id: "session-dynamic", originalRequest: canonical,
            state: .init(iteration: 0, messages: canonical.messages),
            runLimits: .default, contextMode: .dynamic,
            contextPolicy: policy,
            contextWorkingSet: try await allocator.snapshot("session-dynamic"),
            contextTransitions: await allocator.recordedOperations(for: "session-dynamic")
        )
        let encoded = try JSONEncoder().encode(checkpoint)
        let restored = try JSONDecoder().decode(AgentRunner.Checkpoint.self, from: encoded)
        try Expect.equal(restored.contextMode, .dynamic,
            "Session mode is persisted across checkpoint decoding")
        try Expect.equal(restored.contextPolicy, policy,
            "History and allocation policies survive checkpoint decoding")
        try Expect.equal(restored.contextWorkingSet?.allocations.count, 1,
            "Allocation working set survives checkpoint decoding")
        let replay = try Context.Allocator(policy: policy)
        if let saved = restored.contextWorkingSet {
            try await replay.restore(saved, transitions: restored.contextTransitions)
            try Expect.equal(try await replay.snapshot("session-dynamic"), saved,
                "Transition replay reconstructs the exact allocated working set")
        }
        return [
            .message("Deterministic dynamic context retains complete turns, budgets evidence and preserves checkpoint history"),
            .field("omitted_history", String(first.history.omitted.count)),
            .field("selected_evidence", String(second.frame.items.count))
        ]
    }
}
