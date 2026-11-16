import Agentic
import AgenticSessions
import Primitives

/// The runtime's stores, read through the Sessions domain's services. Each
/// runtime type is translated here, and only here, into Sessions records.

extension Run.Log: Sessions.LogReading {
    public func lines() async throws -> (session: String, lines: [Sessions.LogLine]) {
        let contents = try read()
        return (contents.header.session, contents.entries.map(\.sessionsLine))
    }

    public func step(seq: Int) async throws -> (line: Sessions.LogLine, detail: JSONValue)? {
        guard let entry = try read().entries.first(where: { $0.seq == seq }) else {
            return nil
        }
        return (entry.sessionsLine, try detail(of: entry))
    }

    public func payload(digest: String) async throws -> JSONValue {
        try payload(.init(rawValue: digest), as: JSONValue.self)
    }
}

extension Run.Log.Entry {
    var sessionsLine: Sessions.LogLine {
        .init(seq: seq, time: time, run: run, kind: kind, call: callID, summary: summary)
    }
}

extension AgentSessionCatalog: Sessions.CatalogReading {
    public func sessions(statuses: [Sessions.Status], includeArchived: Bool) async throws -> [Sessions.Summary] {
        try listSessions(statuses: statuses, includeArchived: includeArchived)
    }

    public func branches(parentSessionID: String) async throws -> [Sessions.Summary] {
        try listBranches(parentSessionID: parentSessionID)
    }

    public func session(id: String) async throws -> Sessions.Summary {
        try loadSession(sessionID: id)
    }

    public func inspection(sessionID: String) async throws -> Sessions.Inspection {
        try await inspectSession(sessionID: sessionID)
    }

    public func transcript(sessionID: String) async throws -> [TranscriptEvent] {
        try await loadTranscript(sessionID: sessionID)
    }

    public func approvals(sessionID: String) async throws -> [Sessions.ApprovalEvent] {
        try await loadApprovals(sessionID: sessionID)
    }

    public func artifacts(sessionID: String, kinds: [AgentArtifactKind], latestFirst: Bool) async throws -> [AgentArtifact] {
        try await listArtifacts(sessionID: sessionID, kinds: kinds, latestFirst: latestFirst, limit: nil)
    }

    public func artifact(sessionID: String, id: String) async throws -> AgentArtifactRecord {
        try await loadArtifact(sessionID: sessionID, id: id)
    }
}

/// Fed by run state as runs progress, so `read_session_history` sees every
/// session's canonical messages.
extension Sessions.HistoryStore: AgentRunStateSink {
    public func publish(
        _ snapshot: AgentRunStateSnapshot
    ) async {
        record(snapshot.state.messages, sessionID: snapshot.sessionID)
    }
}
