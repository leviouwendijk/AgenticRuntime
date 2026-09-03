import Agentic

public actor AgentTranscriptRecorder: AgentRunEventSink {
    public let store: any AgentTranscriptStore

    public init(
        store: any AgentTranscriptStore
    ) {
        self.store = store
    }

    public func recordMessage(
        _ message: AgentMessage
    ) async throws {
        try await store.append(
            .message(message)
        )
    }

    public func recordToolCall(
        _ toolCall: AgentToolCall
    ) async throws {
        try await store.append(
            .tool_call(toolCall)
        )
    }

    public func recordToolResult(
        _ result: AgentToolResult
    ) async throws {
        try await store.append(
            .tool_result(result)
        )
    }

    public func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws {
        guard shouldPersistAsNote(
            event
        ) else {
            return
        }

        try await store.append(
            .note(
                id: event.id,
                text: noteText(
                    for: event
                )
            )
        )
    }

    public func recordSessionBranch(
        _ event: AgentSessionBranchEvent
    ) async throws {
        try await store.append(
            .session_branch(event)
        )
    }
}

private extension AgentTranscriptRecorder {
    func shouldPersistAsNote(
        _ event: AgentRunEvent
    ) -> Bool {
        switch event.kind {
        case .assistant_response,
             .tool_result,
             .tool_error:
            return false

        case .run_failed,
             .compaction,
             .model_stream_started,
             .assistant_delta,
             .model_stream_tool_call,
             .model_stream_completed,
             .model_stream_interrupted,
             .model_stream_failed,
             .tool_preflight,
             .tool_approved,
             .tool_denied,
             .tool_skipped,
             .pending_approval,
             .pending_user_input,
             .cost_projected,
             .cost_actual:
            return true
        }
    }

    func noteText(
        for event: AgentRunEvent
    ) -> String {
        var lines: [String] = [
            "run_event \(event.kind.rawValue)",
            "iteration=\(event.iteration)"
        ]

        if let messageID = event.messageID {
            lines.append(
                "messageID=\(messageID)"
            )
        }

        if let toolCallID = event.toolCallID {
            lines.append(
                "toolCallID=\(toolCallID)"
            )
        }

        if let toolName = event.toolName {
            lines.append(
                "toolName=\(toolName)"
            )
        }

        if !event.summary.isEmpty {
            lines.append(
                "summary=\(event.summary)"
            )
        }

        return lines.joined(
            separator: "\n"
        )
    }
}
