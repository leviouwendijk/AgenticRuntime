import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runContextCompactionProjection() throws -> [TestDiagnostic] {
        let originals: [Message] = [
            .init(id: "sys", role: .system, content: .init(text: "System")),
            .init(id: "u0", role: .user, content: .init(text: "First question")),
            .init(id: "a0", role: .assistant, content: .init(text: "First answer")),
            .init(id: "u1", role: .user, content: .init(text: "Second question")),
            .init(id: "a1", role: .assistant, content: .init(text: "Second answer")),
            .init(id: "u2", role: .user, content: .init(text: "Third question")),
            .init(id: "a2", role: .assistant, content: .init(text: "Third answer")),
            .init(id: "u3", role: .user, content: .init(text: "Current instruction"))
        ]
        let strategy = CompactionStrategy(
            trigger: .init(maxMessageCount: 5, minimumCompactedMessageCount: 2),
            retention: .init(preserveLeadingSystemMessages: true,
                             preserveRecentMessageCount: 3)
        )
        let compactor = AgentCompactor(strategy: strategy)
        guard let first = compactor.project(messages: originals, iteration: 3),
              let second = compactor.project(messages: originals, iteration: 3) else {
            throw ContextProjectionFixtureError.noProjection
        }
        try Expect.equal(originals.map(\.id),
            ["sys", "u0", "a0", "u1", "a1", "u2", "a2", "u3"],
            "Canonical source is never rewritten")
        try Expect.equal(first.messages.first?.id, "sys", "System preserved")
        try Expect.equal(first.messages.last?.id, "u3", "Current user preserved")
        try Expect.equal(first.history.summaryMessageID,
                         second.history.summaryMessageID, "Projection ID stable")
        try Expect.equal(first.messages.count < originals.count, true,
                         "Model projection has fewer messages")
        return [.field("canonical", String(originals.count)),
                .field("projected", String(first.messages.count))]
    }
}

private enum ContextProjectionFixtureError: Error { case noProjection }
