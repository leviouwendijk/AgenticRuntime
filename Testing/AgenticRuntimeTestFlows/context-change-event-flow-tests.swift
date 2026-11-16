import Agentic
import AgenticSessions
import AgenticContext
import AgenticRuntime
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    /// What a dynamic request leaves out of the transcript is a run event
    /// naming each decision; nothing leaves the model's view unreported.
    static func runContextChangeEvent() async throws -> [TestDiagnostic] {
        let model = ContextChangeModel()
        let executor = AgentExecutor(
            model: .init(invoker: model),
            configuration: .init(
                contextMode: .dynamic,
                contextPolicy: .init(
                    preferredInputTokens: 1_000,
                    maximumInputTokens: 20_000,
                    reservedOutputTokens: 200,
                    history: .init(maximumTurns: 4, maximumTokens: 1_500, elideResultsOver: 128, mode: .fitted)
                )
            ),
            capabilityState: AgentCapabilityState(installed: .none)
        )
        let call = FunctionCall(id: "read.1", name: "read_file", input: .null)
        let result = try await executor.run(
            AgentRequest(messages: [
                Message(id: "ask", role: .user, content: .init(text: "Read the file.")),
                Message(id: "call", role: .assistant, content: .init(blocks: [.call(call)])),
                Message(id: "result", role: .tool, content: .init(blocks: [.result(.init(
                    call: call.reference,
                    output: .string(String(repeating: "source line\n", count: 1_500))
                ))])),
                Message(id: "answer", role: .assistant, content: .init(text: "Findings: A, B, C.")),
                Message(id: "followup", role: .user, content: .init(text: "Implement A, B and C.")),
            ]),
            sessionID: "context-change-run"
        )

        let changed = result.events.filter { $0.kind == .context_changed }
        try Expect.equal(changed.count, 1, "one event for the request's decisions")
        let changes = changed.first?.contextChanges ?? []
        try Expect.true(
            changes.contains { $0.messageID == "result" && $0.call?.id == "read.1" },
            "the shortened result is named with its call: \(changes)"
        )
        let sent = await model.lastRequest()?.messages.map(\.id) ?? []
        try Expect.true(
            sent.contains("answer") && sent.contains("followup"),
            "the answer the follow-up refers to is sent: \(sent)"
        )
        return [.field("context_changed", changed.first?.summary ?? "")]
    }
}

extension AgenticProgramRuntimeFlowTesting {
    /// Append-only by default: a request that would not fit pauses before
    /// dispatch; a compaction (pointers to preserved results) lets it go on.
    /// Past the soft limit, the run is advised, once, and nothing changes.
    static func runContextPauseAndCompaction() async throws -> [TestDiagnostic] {
        func turn(_ id: Int) -> [Message] {
            let call = FunctionCall(id: "read.\(id)", name: "read_file", input: .null)
            return [
                Message(id: "ask.\(id)", role: .user, content: .init(text: "Read file \(id).")),
                Message(id: "call.\(id)", role: .assistant, content: .init(blocks: [.call(call)])),
                Message(id: "result.\(id)", role: .tool, content: .init(blocks: [.result(.init(
                    call: call.reference,
                    output: .string(String(repeating: "source \(id) line\n", count: 1_200))
                ))])),
                Message(id: "answer.\(id)", role: .assistant, content: .init(text: "Read \(id).")),
            ]
        }
        let request = AgentRequest(messages: turn(0) + turn(1) + [
            Message(id: "followup", role: .user, content: .init(text: "Now summarize both.")),
        ])
        let empty = Context.Frame(
            workingSetID: "w", items: [], skippedAllocationIDs: [], inputBudget: 0, estimatedInputTokens: 0
        )
        let full = try Context.InferencePreparer.prepare(
            request: request, frame: empty, delivery: .dynamic, maximumInputTokens: 1_000_000
        ).measurement.estimatedInputTokens
        let plan = Context.Compactor.plan(messages: request.messages)
        let compacted = try Context.InferencePreparer.prepare(
            request: request, frame: empty, delivery: .dynamic, maximumInputTokens: 1_000_000,
            compactions: plan.map { [$0] } ?? []
        ).measurement.estimatedInputTokens
        try Expect.true(plan != nil && compacted < full * 2 / 3, "the fixture compacts substantially")

        let history = Sessions.HistoryStore()
        func executor(limit: Int, ledger: Context.CompactionLedger, store: ContextPauseStore) -> AgentExecutor {
            AgentExecutor(
                model: .init(invoker: ContextChangeModel()),
                configuration: .init(
                    contextMode: .dynamic,
                    contextPolicy: .init(preferredInputTokens: 500, maximumInputTokens: limit, reservedOutputTokens: 100),
                    historyPersistenceMode: .checkpointmutation
                ),
                capabilityState: AgentCapabilityState(installed: .none),
                recording: .init(historyStore: store, stateSinks: [history]),
                contextServices: .init(
                    resolver: Context.UnmountedResolver(),
                    modelContextLimit: 10_000_000,
                    compactions: ledger
                )
            )
        }

        // Hard: the request does not fit, so the run pauses before sending.
        let ledger = Context.CompactionLedger()
        let store = ContextPauseStore()
        let paused = executor(limit: (full + compacted) / 2, ledger: ledger, store: store)
        let first = try await paused.run(request, sessionID: "context-pause")
        guard case .context(_, _, let compactable)? = first.pendingRunLimit,
              let interaction = first.interactionRequest
        else {
            try Expect.true(false, "the run pauses on its context limit: \(String(describing: first.pendingRunLimit))")
            return []
        }
        try Expect.true(compactable > 0, "the pause says what compacting would free")

        await ledger.record(Context.Compactor.plan(messages: request.messages)!)
        let resumed = try await paused.resume(interaction: .init(
            request: interaction,
            resolution: .run_limit(.continue_with(.default))
        ))
        try Expect.true(resumed.isCompleted, "after compacting, the run continues and completes")
        try Expect.true(
            resumed.events.contains { $0.kind == .context_changed && ($0.contextChanges ?? []).contains { $0.reason == .compacted } },
            "the compaction is reported as a context change"
        )

        // The pointer resolves: the message it names, without a session ID.
        let pointer = await ledger.compactions.first?.pointers.first
        let read = try await Sessions.Tools.History().call(
            .init(fromMessageID: pointer?.messageID, throughMessageID: pointer?.messageID),
            in: ToolContext(services: try ToolServices().inserting(history))
        )
        try Expect.equal(read.sessionID, "context-pause", "the session is found from the message")
        try Expect.true(
            read.messages.first?.content == request.messages.first { $0.id == pointer?.messageID }?.content,
            "the full result is read back"
        )

        // Soft: past 60% of the limit, advised once; nothing is changed.
        let advised = try await executor(limit: full * 4 / 3, ledger: .init(), store: .init())
            .run(request, sessionID: "context-soft")
        try Expect.true(advised.isCompleted, "soft pressure does not stop the run")
        try Expect.equal(advised.events.filter { $0.kind == .context_pressure }.count, 1, "advised once")
        try Expect.true(
            !advised.events.contains { $0.kind == .context_changed },
            "and nothing was shortened"
        )
        return [
            .field("full", String(full)),
            .field("compacted", String(compacted)),
            .field("pressure", advised.events.first { $0.kind == .context_pressure }?.summary ?? ""),
        ]
    }
}

private actor ContextPauseStore: AgentHistoryStore {
    private var values: [String: AgentExecutor.Checkpoint] = [:]

    func loadCheckpoint(sessionID: String) async throws -> AgentExecutor.Checkpoint? {
        values[sessionID]
    }

    func saveCheckpoint(_ checkpoint: AgentExecutor.Checkpoint) async throws {
        values[checkpoint.id] = checkpoint
    }

    func deleteCheckpoint(sessionID: String) async throws {
        values.removeValue(forKey: sessionID)
    }
}

private actor ContextChangeModel: AgentModelInvoking {
    private var requests: [AgentRequest] = []

    func lastRequest() -> AgentRequest? { requests.last }

    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocation.Result {
        requests.append(invocation.request)
        let profile = AgentModelProfile(
            identifier: "fixture.context",
            gatewayIdentifier: "fixture.context",
            model: "fixture",
            purposes: [invocation.selection.purpose]
        )
        return .init(
            response: AgentResponse(
                message: Message(role: .assistant, text: "done"),
                stopReason: .end_turn
            ),
            route: .init(
                route: .init(purpose: invocation.selection.purpose, profile: profile),
                diagnostics: [],
                requestMetadata: invocation.request.metadata,
                responseMetadata: [:],
                usage: nil
            )
        )
    }

    nonisolated func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<AgentModelInvocation.Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.completed(try await self.buffered(invocation)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
