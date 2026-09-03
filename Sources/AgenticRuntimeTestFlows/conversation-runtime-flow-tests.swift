import Agentic
import AgenticExecution
import AgenticIO
import AgenticInterfaces
import AgenticRuntime
import AgenticRuntimeCommands
import AgenticTools
import Foundation
import Primitives
import TestFlows

private struct ConversationRuntimeProfileProvider:
    AgentModelProfileProvider
{
    func profiles() throws -> [AgentModelProfile] {
        [
            .init(
                identifier: "conversation-scripted",
                adapterIdentifier: "conversation-scripted",
                model: "scripted",
                title: "Conversation Scripted",
                capabilities: [
                    .text,
                    .streaming,
                ],
                cost: .free,
                latency: .low,
                privacy: .local_private
            ),
        ]
    }
}

private struct ConversationRuntimeModelProvider:
    AgentModelProvider
{
    let modelAdapter: AdapterFlowScriptedModelAdapter

    let descriptor = AgentModelProviderDescriptor(
        source: "conversation-scripted",
        adapterIdentifier: "conversation-scripted",
        displayName: "Conversation Scripted"
    )

    var adapter: AgentModelAdapterFactory? {
        .init {
            modelAdapter
        }
    }

    var profileProvider: (any AgentModelProfileProvider)? {
        ConversationRuntimeProfileProvider()
    }
}

enum AgenticRuntimeConversationFlowTesting {
    static func run() async throws -> [TestFlowDiagnostic] {
        let findCall = AgentToolCall(
            id: "conversation-find-tools-call",
            name: FindToolsTool.identifier.rawValue,
            input: try JSONToolBridge.encode(
                FindToolsToolInput(
                    query: AdapterFlowEchoTool.identifier.rawValue,
                    maximumResults: 1
                )
            )
        )
        let echoCall = AgentToolCall(
            id: "conversation-echo-call",
            name: AdapterFlowEchoTool.identifier.rawValue,
            input: try JSONToolBridge.encode(
                AdapterFlowEchoToolInput(
                    text: "conversation payload"
                )
            )
        )
        let findResponse = AgentResponse(
            message: .init(
                role: .assistant,
                content: .init(
                    blocks: [
                        .tool_call(
                            findCall
                        ),
                    ]
                )
            ),
            stopReason: .tool_use
        )
        let echoResponse = AgentResponse(
            message: .init(
                role: .assistant,
                content: .init(
                    blocks: [
                        .tool_call(
                            echoCall
                        ),
                    ]
                )
            ),
            stopReason: .tool_use
        )
        let finalResponse = AgentResponse(
            message: .init(
                role: .assistant,
                text: "conversation tool ok"
            ),
            stopReason: .end_turn
        )
        let scriptedAdapter = AdapterFlowScriptedModelAdapter(
            streamBatches: [
                [
                    .toolcall(
                        findCall
                    ),
                    .completed(
                        findResponse
                    ),
                ],
                [
                    .toolcall(
                        echoCall
                    ),
                    .completed(
                        echoResponse
                    ),
                ],
                [
                    .completed(
                        finalResponse
                    ),
                ],
            ]
        )
        let application = Agentic.application(
            "conversation-runtime-fixture"
        ) {
            tools {
                AdapterFlowEchoTool()
            }
            modelProvider(
                ConversationRuntimeModelProvider(
                    modelAdapter: scriptedAdapter
                )
            )
        }
        let runtime = try await AgenticRuntime(
            application: application
        )
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-conversation-runtime-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: workspaceRoot,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: workspaceRoot)
        }

        var conversation = try AgenticConversationSession(
            runtime: runtime,
            workspacePath: workspaceRoot.path,
            sessionID: "conversation-runtime"
        )
        let submission = AgenticConversationSubmission(
            body: "Use the echo tool.",
            origin: .transcribed,
            contents: [
                .init(
                    id: "pinned-1",
                    kind: .transcribed,
                    title: "Pinned note",
                    summary: "one note",
                    body: "exact pinned body"
                ),
            ],
            modelProfileID: "conversation-scripted",
            skillIDs: [],
            toolExposure: .discovery
        )
        let result = try await conversation.submit(
            submission
        )
        let requests = await scriptedAdapter.recordedRequests()
        let run: AgenticHostConsoleRunPresentation = try Expect.notNil(
            conversation.snapshot.hostConsole.runs.first,
            "attached host run"
        )
        let assistant: AgenticConversationMessagePresentation = try Expect.notNil(
            conversation.snapshot.messages.last,
            "assistant message"
        )

        try Expect.equal(
            result.response?.message.content.text,
            "conversation tool ok",
            "final response"
        )
        try Expect.equal(
            requests.count,
            3,
            "model request count"
        )
        try Expect.equal(
            requests[0].tools.map(
                \.name
            ),
            [
                FindToolsTool.identifier.rawValue,
            ],
            "conversation begins with discovery only"
        )
        try Expect.equal(
            requests[1].tools.map(
                \.name
            ),
            [
                AdapterFlowEchoTool.identifier.rawValue,
                FindToolsTool.identifier.rawValue,
            ],
            "discovered tool is advertised on the next turn"
        )
        try Expect.equal(
            requests[2].tools.map(
                \.name
            ),
            [
                AdapterFlowEchoTool.identifier.rawValue,
                FindToolsTool.identifier.rawValue,
            ],
            "discovered tool remains exposed for the run"
        )
        try Expect.equal(
            requests.first?.metadata["conversation_input_origin"],
            "transcribed",
            "conversation input origin metadata"
        )
        try Expect.equal(
            requests.first?.metadata["conversation_tool_exposure"],
            "discovery",
            "conversation tool exposure metadata"
        )
        try Expect.equal(
            conversation.snapshot.selectedToolExposure,
            AgenticConversationToolExposure.discovery,
            "conversation retains discovery exposure selection"
        )
        try Expect.contains(
            requests.first?.messages.first?.content.text ?? "",
            "Tool exposure is discovery-only.",
            "discovery system prompt"
        )
        try Expect.equal(
            assistant.body,
            "conversation tool ok",
            "assistant presentation"
        )
        try Expect.equal(
            assistant.attachments,
            [
                AgenticConversationAttachmentPresentation.run(
                    runID: result.sessionID
                ),
            ],
            "assistant run attachment"
        )
        try Expect.equal(
            run.state,
            AgenticHostConsoleRunState.completed,
            "attached run state"
        )
        try Expect.equal(
            run.steps.map(
                \.title
            ),
            [
                FindToolsTool.identifier.rawValue,
                AdapterFlowEchoTool.identifier.rawValue,
            ],
            "attached run records discovery then execution"
        )
        try Expect.equal(
            run.steps.last?.state,
            Optional(
                AgenticHostConsoleStepState.completed
            ),
            "attached tool outcome"
        )
        try Expect.contains(
            conversation.input(for: result.sessionID) ?? "",
            "# Transcribed content: Pinned note",
            "retained transcribed content heading"
        )
        try Expect.contains(
            conversation.input(for: result.sessionID) ?? "",
            "exact pinned body",
            "retained run input"
        )
        try Expect.contains(
            conversation.output(for: result.sessionID) ?? "",
            "\"sessionID\" : \"conversation-runtime-turn-1\"",
            "retained run output"
        )
        try Expect.equal(
            conversation.snapshot.hostConsole.documents.first?.kind,
            Optional(
                AgenticHostConsoleDocumentKind.details
            ),
            "run details document"
        )

        return [
            .field(
                "workspace",
                conversation.snapshot.workspace
            ),
            .field(
                "model_calls",
                String(
                    requests.count
                )
            ),
            .field(
                "run",
                run.id
            ),
            .field(
                "steps",
                String(
                    run.steps.count
                )
            ),
            AdapterRuntimeFlowDiagnostics.events(
                result.events
            ),
        ]
    }

    static func runToolExposureSelection() async throws -> [TestFlowDiagnostic] {
        let response = AgentResponse(
            message: .init(
                role: .assistant,
                text: "all tools exposure ok"
            ),
            stopReason: .end_turn
        )
        let adapter = AdapterFlowScriptedModelAdapter(
            streamBatches: [
                [
                    .completed(
                        response
                    ),
                ],
            ]
        )
        let application = Agentic.application(
            "conversation-tool-exposure-runtime-fixture"
        ) {
            tools {
                AdapterFlowEchoTool()
            }
            modelProvider(
                ConversationRuntimeModelProvider(
                    modelAdapter: adapter
                )
            )
        }
        let runtime = try await AgenticRuntime(
            application: application
        )
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-conversation-tool-exposure-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: workspaceRoot,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: workspaceRoot
            )
        }

        var conversation = try AgenticConversationSession(
            runtime: runtime,
            workspacePath: workspaceRoot.path,
            sessionID: "conversation-tool-exposure-runtime"
        )
        _ = try await conversation.submit(
            .init(
                body: "Inspect the full tool surface.",
                contents: [],
                modelProfileID: "conversation-scripted",
                skillIDs: [],
                toolExposure: .all
            )
        )

        let requests = await adapter.recordedRequests()
        let first = try Expect.notNil(
            requests.first,
            "all-tools conversation request"
        )
        let advertised = first.tools.map(\.name)

        try Expect.equal(
            advertised.contains(
                AdapterFlowEchoTool.identifier.rawValue
            ),
            true,
            "all exposure advertises registered model-facing tools"
        )
        try Expect.equal(
            first.metadata["conversation_tool_exposure"],
            "all",
            "all exposure metadata"
        )
        try Expect.equal(
            conversation.snapshot.selectedToolExposure,
            AgenticConversationToolExposure.all,
            "conversation retains all-tools selection"
        )
        try Expect.contains(
            first.messages.first?.content.text ?? "",
            "All registered model-facing tools are exposed immediately.",
            "all-tools system prompt"
        )

        return [
            .field(
                "advertised",
                advertised.joined(separator: ",")
            ),
            .field(
                "exposure",
                conversation.snapshot.selectedToolExposure.rawValue
            ),
        ]
    }


    static func runFailureObservability() async throws -> [TestFlowDiagnostic] {
        let persistedCall = AgentToolCall(
            id: "failed-run-persisted-echo",
            name: AdapterFlowEchoTool.identifier.rawValue,
            input: try JSONToolBridge.encode(
                AdapterFlowEchoToolInput(
                    text: "persisted failure payload"
                )
            )
        )
        let persistedResponse = AgentResponse(
            message: .init(
                role: .assistant,
                content: .init(
                    blocks: [
                        .tool_call(
                            persistedCall
                        ),
                    ]
                )
            ),
            stopReason: .tool_use
        )
        let persistedAdapter = AdapterFlowScriptedModelAdapter(
            streamBatches: [
                [
                    .toolcall(
                        persistedCall
                    ),
                    .completed(
                        persistedResponse
                    ),
                ],
            ]
        )
        let sessionsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-runtime-failed-run-\(UUID().uuidString)",
                isDirectory: true
            )
        let historyStore = FileHistoryStore(
            sessionsdir: sessionsDirectory
        )
        defer {
            try? FileManager.default.removeItem(
                at: sessionsDirectory
            )
        }
        let persistedSessionID = "runtime-failed-run-persisted"
        let persistedRunner = AgentRunner(
            adapter: persistedAdapter,
            configuration: .init(
                maximumIterations: 1,
                historyPersistenceMode: .checkpointmutation,
                responseDelivery: .stream
            ),
            toolRegistry: .init(
                tools: [
                    AdapterFlowEchoTool(),
                ]
            ),
            historyStore: historyStore
        )
        let persistedResult = try await persistedRunner.run(
            AgentRequest(
                model: "scripted",
                messages: [
                    .init(
                        role: .user,
                        text: "Keep using the echo tool."
                    ),
                ]
            ),
            sessionID: persistedSessionID
        )
        let persistedCheckpoint = try Expect.notNil(
            try await historyStore.loadCheckpoint(
                sessionID: persistedSessionID
            ),
            "failed checkpoint persisted"
        )
        let restoredResult = try await persistedRunner.resume(
            sessionID: persistedSessionID
        )

        try Expect.equal(
            persistedResult.isFailed,
            true,
            "maximum iteration limit returns a failed run result"
        )
        try Expect.equal(
            persistedResult.failure?.kind,
            Optional(AgentRunFailure.Kind.maximum_iterations_exceeded),
            "failed run kind"
        )
        try Expect.equal(
            persistedResult.state.iteration,
            1,
            "failed run retains loop state"
        )
        try Expect.equal(
            persistedResult.events.last?.kind,
            Optional(AgentRunEvent.Kind.run_failed),
            "failed run records terminal event"
        )
        try Expect.equal(
            persistedCheckpoint.phase,
            AgentHistoryPhase.failed,
            "failed checkpoint phase"
        )
        try Expect.equal(
            persistedCheckpoint.failure?.kind,
            Optional(AgentRunFailure.Kind.maximum_iterations_exceeded),
            "failed checkpoint reason"
        )
        try Expect.equal(
            restoredResult.failure,
            persistedResult.failure,
            "loading a terminal failed session preserves failure outcome"
        )
        try Expect.equal(
            restoredResult.events,
            persistedResult.events,
            "loading a terminal failed session preserves run events"
        )

        let findCall = AgentToolCall(
            id: "conversation-failed-find-tools",
            name: FindToolsTool.identifier.rawValue,
            input: try JSONToolBridge.encode(
                FindToolsToolInput(
                    query: AdapterFlowEchoTool.identifier.rawValue,
                    maximumResults: 1
                )
            )
        )
        let findResponse = AgentResponse(
            message: .init(
                role: .assistant,
                content: .init(
                    blocks: [
                        .tool_call(
                            findCall
                        ),
                    ]
                )
            ),
            stopReason: .tool_use
        )
        var streamBatches: [[AgentStreamEvent]] = [
            [
                .toolcall(
                    findCall
                ),
                .completed(
                    findResponse
                ),
            ],
        ]

        for index in 1..<12 {
            let call = AgentToolCall(
                id: "conversation-failed-echo-\(index)",
                name: AdapterFlowEchoTool.identifier.rawValue,
                input: try JSONToolBridge.encode(
                    AdapterFlowEchoToolInput(
                        text: "loop \(index)"
                    )
                )
            )
            let response = AgentResponse(
                message: .init(
                    role: .assistant,
                    content: .init(
                        blocks: [
                            .tool_call(
                                call
                            ),
                        ]
                    )
                ),
                stopReason: .tool_use
            )

            streamBatches.append(
                [
                    .toolcall(
                        call
                    ),
                    .completed(
                        response
                    ),
                ]
            )
        }

        let conversationAdapter = AdapterFlowScriptedModelAdapter(
            streamBatches: streamBatches
        )
        let application = Agentic.application(
            "conversation-failed-runtime-fixture"
        ) {
            tools {
                AdapterFlowEchoTool()
            }
            modelProvider(
                ConversationRuntimeModelProvider(
                    modelAdapter: conversationAdapter
                )
            )
        }
        let runtime = try await AgenticRuntime(
            application: application
        )
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-conversation-failed-runtime-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: workspaceRoot,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: workspaceRoot
            )
        }

        var conversation = try AgenticConversationSession(
            runtime: runtime,
            workspacePath: workspaceRoot.path,
            sessionID: "conversation-failed-runtime"
        )
        let result: AgentRunResult = try await conversation.submit(
            .init(
                body: "Keep using the echo tool until the run limit is reached.",
                contents: [],
                modelProfileID: "conversation-scripted",
                skillIDs: []
            )
        )
        let requests = await conversationAdapter.recordedRequests()
        let run: AgenticHostConsoleRunPresentation = try Expect.notNil(
            conversation.snapshot.hostConsole.runs.first,
            "failed conversation retains attached host run"
        )
        let assistant: AgenticConversationMessagePresentation = try Expect.notNil(
            conversation.snapshot.messages.last,
            "failed conversation retains assistant presentation"
        )
        let failure: AgentRunFailure = try Expect.notNil(
            result.failure,
            "failed conversation result"
        )

        try Expect.equal(
            result.isFailed,
            true,
            "failed conversation returns structured run outcome"
        )
        try Expect.equal(
            result.state.iteration,
            12,
            "conversation retains all bounded iterations"
        )
        try Expect.equal(
            requests.count,
            12,
            "conversation stops before a thirteenth model request"
        )
        try Expect.equal(
            assistant.body,
            failure.message,
            "failed assistant presentation uses structured failure message"
        )
        try Expect.equal(
            assistant.attachments,
            [
                AgenticConversationAttachmentPresentation.run(
                    runID: result.sessionID
                ),
            ],
            "failed assistant retains run attachment"
        )
        try Expect.equal(
            run.state,
            AgenticHostConsoleRunState.failed,
            "failed run projects failed state"
        )
        try Expect.equal(
            run.summary,
            Optional(failure.message),
            "failed run projects failure summary"
        )
        try Expect.equal(
            run.steps.last?.title,
            Optional("run failure"),
            "failed run exposes terminal failure step"
        )
        try Expect.equal(
            conversation.snapshot.activity,
            "run failed",
            "failed conversation activity"
        )
        try Expect.contains(
            conversation.input(for: result.sessionID) ?? "",
            "Keep using the echo tool",
            "failed run retains input"
        )
        try Expect.contains(
            conversation.output(for: result.sessionID) ?? "",
            "maximum_iterations_exceeded",
            "failed run retains encoded failure output"
        )
        try Expect.contains(
            conversation.snapshot.hostConsole.documents.last?.body ?? "",
            "maximum_iterations_exceeded",
            "failed run exposes terminal failure details"
        )

        return [
            .field(
                "persisted_failure",
                persistedResult.failure?.kind.rawValue ?? "missing"
            ),
            .field(
                "conversation_failure",
                failure.kind.rawValue
            ),
            .field(
                "conversation_model_calls",
                String(requests.count)
            ),
            AdapterRuntimeFlowDiagnostics.events(
                result.events
            ),
        ]
    }
}
