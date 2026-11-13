import Agentic

/// In-memory record of every session's canonical message history, fed by run
/// state snapshots. Compaction only changes request projections, so this keeps
/// what the model no longer sees retrievable without durable storage.
///
/// Hosts register one instance both as a run state sink and as a tool service.
public actor AgentSessionHistory: AgentRunStateSink {
    private var messagesBySessionID: [String: [Message]]

    public init() {
        self.messagesBySessionID = [:]
    }

    public func publish(
        _ snapshot: AgentRunStateSnapshot
    ) async {
        messagesBySessionID[snapshot.sessionID] = snapshot.state.messages
    }

    public func messages(
        sessionID: String
    ) -> [Message]? {
        messagesBySessionID[sessionID]
    }

    public func sessionIDs() -> [String] {
        messagesBySessionID.keys.sorted()
    }
}
