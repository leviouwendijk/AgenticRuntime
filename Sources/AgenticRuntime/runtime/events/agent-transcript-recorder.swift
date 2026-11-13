import Agentic

public actor AgentTranscriptRecorder: Run.EventSink {
    public let store: any TranscriptStore

    public init(
        store: any TranscriptStore
    ) {
        self.store = store
    }

    public func record(
        _ event: Run.Event
    ) async throws {
        switch event {
        case .state(let state):
            guard shouldPersistAsNote(
                state
            ) else {
                return
            }

            try await store.append(
                .note(
                    id: state.id,
                    text: noteText(
                        for: state
                    )
                )
            )

        case .tool_observation, .request:
            return
        }
    }

    public func recordMessage(
        _ message: Message
    ) async throws {
        try await store.append(
            .message(message)
        )
    }

    public func recordFunctionCall(
        _ functionCall: FunctionCall
    ) async throws {
        try await store.append(
            .call(functionCall)
        )
    }

    public func recordToolResult(
        _ result: FunctionCall.Response
    ) async throws {
        try await store.append(
            .result(result)
        )
    }

    public func recordSessionBranch(
        _ event: SessionBranchEvent
    ) async throws {
        try await store.append(
            .session_branch(event)
        )
    }
}

private extension AgentTranscriptRecorder {
    func shouldPersistAsNote(
        _ event: Run.Event.State
    ) -> Bool {
        switch event.kind {
        case .assistant_response,
             .context_usage,
             .tool_result,
             .tool_error:
            return false

        case .run_failed,
             .run_limit_reached,
             .run_limit_continued,
             .run_limit_stopped,
             .run_interrupted,
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
             .pending_workspace_access,
             .cost_projected,
             .cost_actual,
             .mutation_staged,
             .mutation_published,
             .mutation_withdrawn:
            return true
        }
    }

    func noteText(
        for event: Run.Event.State
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

        if let callID = event.callID {
            lines.append(
                "callID=\(callID)"
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
