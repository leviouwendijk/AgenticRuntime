import Agentic
import AgenticRuntime
import TestFlows

private actor ContextTranscriptFixture: TranscriptStore {
    private var events: [TranscriptEvent]

    init(_ events: [TranscriptEvent]) {
        self.events = events
    }

    func loadEvents() async throws -> [TranscriptEvent] { events }
    func append(_ event: TranscriptEvent) async throws { events.append(event) }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runContextEvidenceResolution() async throws -> [TestDiagnostic] {
        let previous = Message(
            id: "old-user", role: .user,
            content: .init(text: "Original instruction from another session")
        )
        let first = ContextTranscriptFixture([.message(previous)])
        let second = ContextTranscriptFixture([
            .note(id: "failure", text: "Tool mutation failed because matching context was stale")
        ])
        let resolver = Context.SessionEvidenceResolver(
            authorizedSessions: ["session-A", "session-B"],
            transcripts: ["session-A": first, "session-B": second]
        )
        let originalPointer = Context.Pointer(
            source: "session/session-A", record: "event/0"
        )
        let observed = try await resolver.resolve(originalPointer)
        try Expect.equal(observed.messages[0].role, .assistant,
            "Historical user messages are evidence, not fresh user instructions")
        try Expect.equal(observed.messages[0].content.text.contains(previous.content.text), true,
            "Original message content remains recoverable")
        try Expect.equal(observed.messages[0].content.text.contains("session/session-A"), true,
            "Evidence identifies original source")
        guard case .recorded(let version) = observed.pointer.revision else {
            throw ContextEvidenceError.unavailableRecord("expected recorded revision")
        }
        try Expect.equal(version.hasPrefix("sha256:"), true,
            "Observed evidence has content-derived identity")

        let pinned = Context.Pointer(
            source: originalPointer.source, record: originalPointer.record,
            revision: observed.pointer.revision
        )
        let unchanged = try await resolver.resolve(pinned)
        try Expect.equal(unchanged.pointer, observed.pointer,
            "Pinned reference matches the original content")

        var stale = false
        do {
            _ = try await resolver.resolve(.init(
                source: originalPointer.source, record: originalPointer.record,
                revision: .recorded("sha256:obsolete")
            ))
        } catch ContextEvidenceError.recordedRevisionMismatch {
            stale = true
        }
        try Expect.equal(stale, true, "Historical version mismatch never substitutes new data")

        var denied = false
        do {
            _ = try await resolver.resolve(.init(
                source: "session/other", record: "event/0"
            ))
        } catch ContextEvidenceError.unauthorizedSession {
            denied = true
        }
        try Expect.equal(denied, true, "Cross-session retrieval requires explicit authorization")

        let allocator = try Context.Allocator(policy: .init(
            preferredInputTokens: 2_000, maximumInputTokens: 8_000,
            reservedOutputTokens: 100, maximumResolutions: 4
        ))
        try await allocator.createWorkingSet(id: "evidence-worker")
        try await allocator.apply([
            .allocate(.init(id: "old-user", pointer: originalPointer, required: true)),
            .allocate(.init(id: "failed-run", pointer: .init(
                source: "session/session-B", record: "event/0"
            ), required: true))
        ], to: "evidence-worker")
        let frame = try await allocator.prepareFrame(
            for: "evidence-worker", using: resolver, modelContextLimit: 10_000
        )
        try Expect.equal(frame.items.count, 2, "Evidence from two sessions shares one working set")
        try Expect.equal(frame.messages.allSatisfy { $0.role == .assistant }, true,
            "Heterogeneous historical evidence does not gain elevated roles")
        return [
            .message("Context evidence resolves session events with explicit authorization and pinned revisions"),
            .field("sources", "2"),
            .field("items", String(frame.items.count))
        ]
    }
}
