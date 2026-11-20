import Agentic
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runContextCompactionProjection() throws -> [TestDiagnostic] {
        // Long enough that the quantized cut (AgentCompactor.boundaryStep)
        // lands past the system prefix.
        let turns = (0..<11).flatMap { index -> [Message] in
            [
                .init(id: "u\(index)", role: .user, content: .init(text: "Question \(index)")),
                .init(id: "a\(index)", role: .assistant, content: .init(text: "Answer \(index)")),
            ]
        }
        let originals: [Message] =
            [.init(id: "sys", role: .system, content: .init(text: "System"))]
            + turns
            + [.init(id: "u11", role: .user, content: .init(text: "Current instruction"))]
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
        try Expect.equal(originals.count, 24, "Canonical source is never rewritten")
        try Expect.equal(originals.last?.id, "u11", "Canonical order is kept")
        try Expect.equal(first.messages.first?.id, "sys", "System preserved")
        try Expect.equal(first.messages.last?.id, "u11", "Current user preserved")
        try Expect.equal(first.history.summaryMessageID,
                         second.history.summaryMessageID, "Projection ID stable")
        try Expect.equal(first.messages.count < originals.count, true,
                         "Model projection has fewer messages")
        return [.field("canonical", String(originals.count)),
                .field("projected", String(first.messages.count))]
    }
}

private enum ContextProjectionFixtureError: Error { case noProjection }
