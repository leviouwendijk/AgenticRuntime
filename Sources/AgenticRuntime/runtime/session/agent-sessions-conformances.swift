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

/// The sessions a host records in its durable logs, as a catalog: what the
/// host actually wrote, not a separate store it may never fill. Artifacts
/// are not part of a log, so there are none.
extension Run.Log.Store: Sessions.CatalogReading {
    public func sessions(statuses: [Sessions.Status], includeArchived _: Bool) async throws -> [Sessions.Summary] {
        try summaries().map(summary).filter { statuses.isEmpty || statuses.contains($0.metadata.status) }
    }

    public func branches(parentSessionID: String) async throws -> [Sessions.Summary] {
        try summaries().map(summary).filter { $0.metadata.branch?.parentSessionID == parentSessionID }
    }

    public func session(id: String) async throws -> Sessions.Summary {
        guard let found = try summaries().first(where: { $0.session == id }) else {
            throw AgentSessionCatalogError.sessionNotFound(id)
        }
        return try summary(found)
    }

    public func inspection(sessionID: String) async throws -> Sessions.Inspection {
        let summary = try await session(id: sessionID)
        return .init(
            summary: summary,
            transcriptEventCount: try await transcript(sessionID: sessionID).count,
            approvalEventCount: try await approvals(sessionID: sessionID).count,
            childBranchCount: try await branches(parentSessionID: sessionID).count
        )
    }

    public func transcript(sessionID: String) async throws -> [TranscriptEvent] {
        try read(session: sessionID).entries.compactMap { entry -> TranscriptEvent? in
            switch entry.body {
            case .message(let stored):
                return (try? payload(stored.digest, as: Message.self, session: sessionID)).map(TranscriptEvent.message)
            case .branch(let event):
                return .session_branch(event)
            case .state, .observation, .request, .call, .response:
                return nil
            }
        }
    }

    public func approvals(sessionID: String) async throws -> [Sessions.ApprovalEvent] {
        try read(session: sessionID).entries.compactMap { entry in
            guard case .state(let state) = entry.body else { return nil }
            return Sessions.ApprovalEvent(sessionID: sessionID, runEvent: state)
        }
    }

    public func artifacts(sessionID: String, kinds _: [AgentArtifactKind], latestFirst _: Bool) async throws -> [AgentArtifact] {
        _ = try await session(id: sessionID)
        return []
    }

    public func artifact(sessionID _: String, id: String) async throws -> AgentArtifactRecord {
        throw AgentArtifactError.artifactNotFound(id)
    }

    private func summary(
        _ log: Run.Log.Summary
    ) throws -> Sessions.Summary {
        let contents = try read(session: log.session)
        let states = contents.entries.compactMap { entry -> Run.Event.State? in
            if case .state(let state) = entry.body { return state }
            return nil
        }
        let branch = contents.entries.lazy.compactMap { entry -> SessionBranch? in
            if case .branch(let event) = entry.body { return event.branch }
            return nil
        }.first
        // A log records what happened, not a lifecycle: a session waits on
        // the operator while its last pause is unanswered, else it is active.
        let status: Sessions.Status = switch states.last(where: {
            [.pending_approval, .pending_user_input, .tool_approved, .tool_denied, .assistant_response].contains($0.kind)
        })?.kind {
        case .pending_approval?: .awaiting_approval
        case .pending_user_input?: .awaiting_user_input
        default: .active
        }
        let metadata = log.header.metadata
        return .init(
            metadata: .init(
                sessionID: log.session,
                createdAt: log.header.created,
                updatedAt: log.lastActivity,
                title: metadata["title"] ?? log.firstPrompt.map { String($0.prefix(80)) },
                status: status,
                profileID: metadata["model_profile_id"],
                workspaceAttached: metadata["workspace"] != nil,
                branch: branch,
                metadata: metadata
            ),
            hasCheckpoint: false,
            hasTranscript: log.steps > 0,
            hasApprovals: states.contains { Sessions.ApprovalEvent(sessionID: log.session, runEvent: $0) != nil },
            artifactCount: 0
        )
    }
}
