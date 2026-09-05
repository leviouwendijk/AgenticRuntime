import Agentic
import AgenticExecution
import AgenticIO
import AgenticInterfaces
import AgenticRuntime
import AgenticRuntimeCommands
import AgenticTools
import DSL
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
            .init(
                identifier: "conversation-buffered",
                adapterIdentifier: "conversation-scripted",
                model: "buffered",
                title: "Z Conversation Buffered",
                capabilities: [
                    .text,
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

private actor ConversationRuntimeStateSink: AgentRunStateSink {
    private var values: [AgentRunStateSnapshot] = []

    func publish(
        _ snapshot: AgentRunStateSnapshot
    ) async {
        values.append(
            snapshot
        )
    }

    func snapshots() -> [AgentRunStateSnapshot] {
        values
    }
}

private actor ConversationApprovalToolProbe {
    private var invocationCount = 0

    func recordInvocation() {
        invocationCount += 1
    }

    func count() -> Int {
        invocationCount
    }
}

private struct ConversationApprovalTool: AgentTool {
    typealias Input = AdapterFlowEchoToolInput
    typealias Output = AdapterFlowEchoToolOutput

    static let identifier: AgentToolIdentifier = "conversation_approval_tool"
    static let description = "Bounded mutation fixture for conversation approval routing."
    static let risk: ActionRisk = .boundedmutate

    let probe: ConversationApprovalToolProbe

    var identifier: AgentToolIdentifier {
        Self.identifier
    }

    var description: String {
        Self.description
    }

    var risk: ActionRisk {
        Self.risk
    }

    func call(
        _ input: Input,
        context _: AgentToolExecutionContext
    ) async throws -> Output {
        await probe.recordInvocation()
        return AdapterFlowEchoToolOutput(
            text: input.text
        )
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
        let bufferedResponse = AgentResponse(
            message: .init(
                role: .assistant,
                text: "conversation buffered ok"
            ),
            stopReason: .end_turn
        )
        let scriptedAdapter = AdapterFlowScriptedModelAdapter(
            bufferedResponses: [
                bufferedResponse,
            ],
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

        let conversation = try AgenticConversationSession(
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
            toolExposure: .discovery,
            responseDelivery: .stream
        )
        let result = try await conversation.submit(
            submission
        )
        let requests = await scriptedAdapter.recordedRequests()
        let conversationSnapshot = await conversation.snapshot
        let retainedInput = await conversation.input(
            for: result.sessionID
        )
        let retainedOutput = await conversation.output(
            for: result.sessionID
        )
        let run: AgenticHostConsoleRunPresentation = try Expect.notNil(
            conversationSnapshot.hostConsole.runs.first,
            "attached host run"
        )
        let assistant: AgenticConversationMessagePresentation = try Expect.notNil(
            conversationSnapshot.messages.last,
            "assistant message"
        )

        try Expect.equal(
            result.response?.message.content.text,
            "conversation tool ok",
            "final response"
        )
        try Expect.equal(
            AgentRunnerConfiguration.default.autonomyMode,
            AutonomyMode.auto_observe,
            "runner configuration defaults to auto observe"
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
            requests.first?.metadata["conversation_response_delivery"],
            "stream",
            "conversation response delivery metadata"
        )
        try Expect.equal(
            requests.first?.metadata["conversation_autonomy_mode"],
            AutonomyMode.auto_observe.rawValue,
            "conversation autonomy metadata"
        )
        try Expect.equal(
            conversationSnapshot.selectedResponseDelivery,
            AgentModelResponseDelivery.stream,
            "conversation retains streaming response delivery"
        )
        try Expect.equal(
            conversationSnapshot.selectedToolExposure,
            AgenticConversationToolExposure.discovery,
            "conversation retains discovery exposure selection"
        )
        try Expect.equal(
            conversationSnapshot.selectedAutonomyMode,
            AutonomyMode.auto_observe,
            "conversation retains auto-observe autonomy selection"
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
            retainedInput ?? "",
            "# Transcribed content: Pinned note",
            "retained transcribed content heading"
        )
        try Expect.contains(
            retainedInput ?? "",
            "exact pinned body",
            "retained run input"
        )
        try Expect.contains(
            retainedOutput ?? "",
            "\"sessionID\" : \"conversation-runtime-turn-1\"",
            "retained run output"
        )
        try Expect.equal(
            result.toolUses.map(\.toolCall.id),
            [
                findCall.id,
                echoCall.id,
            ],
            "run result retains exact model tool calls"
        )

        let documents =
            conversationSnapshot.hostConsole.documents
        let findDetails = documents.first {
            $0.stepID == findCall.id
                && $0.kind == .details
        }
        let echoDetails = documents.first {
            $0.stepID == echoCall.id
                && $0.kind == .details
        }
        let echoStdout = documents.first {
            $0.stepID == echoCall.id
                && $0.kind == .stdout
        }

        try Expect.contains(
            findDetails?.body ?? "",
            "\"maximumResults\"",
            "find_tools details expose exact model input"
        )
        try Expect.contains(
            findDetails?.body ?? "",
            AdapterFlowEchoTool.identifier.rawValue,
            "find_tools details expose exact discovery query"
        )
        try Expect.contains(
            echoDetails?.body ?? "",
            "\"text\" : \"conversation payload\"",
            "echo details expose exact model input"
        )
        try Expect.contains(
            echoDetails?.body ?? "",
            "Echoed conversation payload.",
            "echo details expose semantic result projection"
        )
        try Expect.contains(
            echoDetails?.body ?? "",
            "echo detail: conversation payload",
            "echo details expose non-stream observation"
        )
        try Expect.contains(
            echoStdout?.body ?? "",
            "echo stdout: conversation payload",
            "echo stdout is projected as a dedicated stream document"
        )

        try Expect.equal(
            findDetails?.structuredBody == nil,
            false,
            "find_tools details retain semantic structured content"
        )
        try Expect.equal(
            echoDetails?.structuredBody == nil,
            false,
            "echo details retain semantic structured content"
        )

        let structuredEncoder = JSONEncoder()
        structuredEncoder.outputFormatting = [
            .sortedKeys,
        ]
        let findStructuredText = try String(
            decoding: structuredEncoder.encode(
                findDetails?.structuredBody
            ),
            as: UTF8.self
        )
        let echoStructuredText = try String(
            decoding: structuredEncoder.encode(
                echoDetails?.structuredBody
            ),
            as: UTF8.self
        )

        try Expect.contains(
            findStructuredText,
            "agentic.tool.input",
            "find_tools structured details preserve semantic input role"
        )
        try Expect.contains(
            findStructuredText,
            "maximumResults",
            "find_tools structured details preserve exact input"
        )
        try Expect.contains(
            findStructuredText,
            AdapterFlowEchoTool.identifier.rawValue,
            "find_tools structured details preserve discovery query"
        )
        try Expect.contains(
            echoStructuredText,
            "agentic.tool.result",
            "echo structured details preserve semantic result role"
        )
        try Expect.contains(
            echoStructuredText,
            "Echoed conversation payload.",
            "echo structured details preserve result summary"
        )
        try Expect.contains(
            echoStructuredText,
            "echo detail: conversation payload",
            "echo structured details preserve non-stream observation"
        )

        let bufferedResult = try await conversation.submit(
            AgenticConversationSubmission(
                body: "Use buffered delivery.",
                contents: [],
                modelProfileID: "conversation-scripted",
                skillIDs: [],
                toolExposure: .discovery,
                responseDelivery: .buffered
            )
        )
        let requestsAfterBuffered = await scriptedAdapter.recordedRequests()
        let snapshotAfterBuffered = await conversation.snapshot

        try Expect.equal(
            bufferedResult.response?.message.content.text,
            "conversation buffered ok",
            "buffered conversation response"
        )
        try Expect.equal(
            requestsAfterBuffered.count,
            4,
            "buffered conversation adds one model request"
        )
        try Expect.equal(
            requestsAfterBuffered.last?.metadata[
                "conversation_response_delivery"
            ],
            "buffered",
            "buffered response delivery metadata"
        )
        try Expect.equal(
            snapshotAfterBuffered.selectedResponseDelivery,
            AgentModelResponseDelivery.buffered,
            "buffered selection remains visible in conversation state"
        )

        await conversation.selectModel(
            "conversation-buffered"
        )
        let nonStreamingModelSnapshot = await conversation.snapshot

        try Expect.equal(
            nonStreamingModelSnapshot.selectedResponseDelivery,
            AgentModelResponseDelivery.buffered,
            "non-streaming model coerces response delivery to buffered"
        )

        await conversation.selectResponseDelivery(
            .stream
        )
        let rejectedStreamingSnapshot = await conversation.snapshot

        try Expect.equal(
            rejectedStreamingSnapshot.selectedResponseDelivery,
            AgentModelResponseDelivery.buffered,
            "non-streaming model rejects streaming selection"
        )

        await conversation.selectModel(
            "conversation-scripted"
        )
        await conversation.selectResponseDelivery(
            .stream
        )
        let restoredStreamingSnapshot = await conversation.snapshot

        try Expect.equal(
            restoredStreamingSnapshot.selectedResponseDelivery,
            AgentModelResponseDelivery.stream,
            "stream-capable model allows streaming selection"
        )

        try await proveEmbeddedApprovalAction(
            workspaceRoot: workspaceRoot
        )

        return [
            .field(
                "workspace",
                conversationSnapshot.workspace
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

    private static func proveEmbeddedApprovalAction(
        workspaceRoot: URL
    ) async throws {
        let probe = ConversationApprovalToolProbe()
        let call = AgentToolCall(
            id: "conversation-approval-call",
            name: ConversationApprovalTool.identifier.rawValue,
            input: try JSONToolBridge.encode(
                AdapterFlowEchoToolInput(
                    text: "approved payload"
                )
            )
        )
        let toolResponse = AgentResponse(
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
        let finalResponse = AgentResponse(
            message: .init(
                role: .assistant,
                text: "conversation approval resumed"
            ),
            stopReason: .end_turn
        )
        let adapter = AdapterFlowScriptedModelAdapter(
            streamBatches: [
                [
                    .toolcall(
                        call
                    ),
                    .completed(
                        toolResponse
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
            "conversation-approval-runtime-fixture"
        ) {
            tools {
                ConversationApprovalTool(
                    probe: probe
                )
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
        let conversation = try AgenticConversationSession(
            runtime: runtime,
            workspacePath: workspaceRoot.path,
            sessionID: "conversation-approval-runtime"
        )
        let initial = try await conversation.submit(
            .init(
                body: "Request the bounded mutation.",
                contents: [],
                modelProfileID: "conversation-scripted",
                skillIDs: [],
                toolExposure: .all,
                responseDelivery: .stream,
                autonomyMode: .auto_observe
            )
        )
        let suspendedSnapshot = await conversation.snapshot
        let interruption: AgenticHostConsoleInterruptionPresentation = try Expect.notNil(
            suspendedSnapshot.hostConsole.interruptions.first(
                where: { interruption in
                    interruption.runID == initial.sessionID
                }
            ),
            "conversation approval interruption"
        )

        try Expect.equal(
            initial.isAwaitingApproval,
            true,
            "conversation bounded mutation suspends for approval"
        )
        try Expect.equal(
            await probe.count(),
            0,
            "conversation bounded mutation does not execute before approval"
        )
        try Expect.equal(
            interruption.stepID,
            call.id,
            "conversation approval interruption retains exact tool call"
        )
        try Expect.equal(
            interruption.actions,
            [
                AgenticHostConsoleAction.approve,
                .deny,
                .skip,
            ],
            "conversation approval interruption exposes resolvable actions"
        )
        try Expect.equal(
            suspendedSnapshot.hostConsole.documents.contains(
                where: { document in
                    document.runID == initial.sessionID
                        && document.stepID == call.id
                        && document.kind == .details
                }
            ),
            true,
            "conversation approval exposes staged tool details"
        )

        let resumed = try await conversation.resolveHostAction(
            interruptionID: interruption.id,
            runID: interruption.runID,
            stepID: interruption.stepID,
            action: .approve
        )
        let completedSnapshot = await conversation.snapshot
        let completedRun: AgenticHostConsoleRunPresentation = try Expect.notNil(
            completedSnapshot.hostConsole.runs.first(
                where: { run in
                    run.id == resumed.sessionID
                }
            ),
            "completed conversation approval run"
        )

        try Expect.equal(
            resumed.isCompleted,
            true,
            "approved conversation run resumes to completion"
        )
        try Expect.equal(
            await probe.count(),
            1,
            "approved conversation bounded mutation executes exactly once"
        )
        try Expect.equal(
            completedRun.state,
            AgenticHostConsoleRunState.completed,
            "approved conversation run projects completed state"
        )
        try Expect.equal(
            completedSnapshot.hostConsole.interruptions.contains(
                where: { interruption in
                    interruption.runID == resumed.sessionID
                }
            ),
            false,
            "resolved conversation approval interruption is removed"
        )
        try Expect.equal(
            completedSnapshot.messages.last?.body,
            Optional("conversation approval resumed"),
            "approved conversation run updates the attached assistant message"
        )
        try Expect.equal(
            await adapter.recordedRequests().count,
            2,
            "approved conversation run continues the model after tool execution"
        )
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

        let conversation = try AgenticConversationSession(
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
        let conversationSnapshot = await conversation.snapshot
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
            conversationSnapshot.selectedToolExposure,
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
                conversationSnapshot.selectedToolExposure.rawValue
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
            toolRegistry: try ToolRegistry {
                AdapterFlowEchoTool()
            },
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

        let bufferedFailureAdapter = AdapterFlowScriptedModelAdapter()
        let bufferedFailureSessionID = "runtime-model-invocation-failed-buffered"
        let bufferedFailureRunner = AgentRunner(
            adapter: bufferedFailureAdapter,
            configuration: .init(
                maximumIterations: 2,
                historyPersistenceMode: .checkpointmutation,
                responseDelivery: .buffered
            ),
            historyStore: historyStore
        )
        let bufferedFailureResult = try await bufferedFailureRunner.run(
            AgentRequest(
                model: "scripted",
                messages: [
                    .init(
                        role: .user,
                        text: "Fail this buffered model invocation."
                    ),
                ]
            ),
            sessionID: bufferedFailureSessionID
        )
        let bufferedFailureCheckpoint = try Expect.notNil(
            try await historyStore.loadCheckpoint(
                sessionID: bufferedFailureSessionID
            ),
            "buffered model failure checkpoint persisted"
        )
        let restoredBufferedFailure = try await bufferedFailureRunner.resume(
            sessionID: bufferedFailureSessionID
        )

        try Expect.equal(
            bufferedFailureResult.failure?.kind,
            Optional(AgentRunFailure.Kind.model_invocation_failed),
            "buffered model invocation becomes structured run failure"
        )
        try Expect.contains(
            bufferedFailureResult.failure?.message ?? "",
            "Scripted model has no buffered response left.",
            "buffered model failure preserves adapter message"
        )
        try Expect.equal(
            bufferedFailureCheckpoint.failure,
            bufferedFailureResult.failure,
            "buffered model failure persists in checkpoint"
        )
        try Expect.equal(
            restoredBufferedFailure.failure,
            bufferedFailureResult.failure,
            "buffered model failure restores as terminal run result"
        )
        try Expect.equal(
            bufferedFailureResult.events.last?.kind,
            Optional(AgentRunEvent.Kind.run_failed),
            "buffered model failure records terminal run event"
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

        let conversation = try AgenticConversationSession(
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
        let conversationSnapshot = await conversation.snapshot
        let retainedInput = await conversation.input(
            for: result.sessionID
        )
        let retainedOutput = await conversation.output(
            for: result.sessionID
        )
        let run: AgenticHostConsoleRunPresentation = try Expect.notNil(
            conversationSnapshot.hostConsole.runs.first,
            "failed conversation retains attached host run"
        )
        let assistant: AgenticConversationMessagePresentation = try Expect.notNil(
            conversationSnapshot.messages.last,
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
            conversationSnapshot.activity,
            "run failed",
            "failed conversation activity"
        )
        try Expect.contains(
            retainedInput ?? "",
            "Keep using the echo tool",
            "failed run retains input"
        )
        try Expect.contains(
            retainedOutput ?? "",
            "maximum_iterations_exceeded",
            "failed run retains encoded failure output"
        )
        try Expect.contains(
            conversationSnapshot.hostConsole.documents.last?.body ?? "",
            "maximum_iterations_exceeded",
            "failed run exposes terminal failure details"
        )

        let invocationFailureAdapter = AdapterFlowScriptedModelAdapter()
        let invocationFailureApplication = Agentic.application(
            "conversation-model-invocation-failed-runtime-fixture"
        ) {
            tools {
                AdapterFlowEchoTool()
            }
            modelProvider(
                ConversationRuntimeModelProvider(
                    modelAdapter: invocationFailureAdapter
                )
            )
        }
        let invocationFailureRuntime = try await AgenticRuntime(
            application: invocationFailureApplication
        )
        let invocationFailureConversation = try AgenticConversationSession(
            runtime: invocationFailureRuntime,
            workspacePath: workspaceRoot.path,
            sessionID: "conversation-model-invocation-failed-runtime"
        )
        let invocationFailureResult = try await invocationFailureConversation.submit(
            .init(
                body: "Trigger a model invocation failure.",
                contents: [],
                modelProfileID: "conversation-scripted",
                skillIDs: [],
                toolExposure: .discovery
            )
        )
        let invocationFailureRequests = await invocationFailureAdapter.recordedRequests()
        let invocationFailureSnapshot = await invocationFailureConversation.snapshot
        let invocationFailureInput = await invocationFailureConversation.input(
            for: invocationFailureResult.sessionID
        )
        let invocationFailureOutput = await invocationFailureConversation.output(
            for: invocationFailureResult.sessionID
        )
        let invocationFailure = try Expect.notNil(
            invocationFailureResult.failure,
            "conversation model invocation failure"
        )
        let invocationFailureRun = try Expect.notNil(
            invocationFailureSnapshot.hostConsole.runs.first,
            "conversation model invocation failure retains host run"
        )
        let invocationFailureAssistant = try Expect.notNil(
            invocationFailureSnapshot.messages.last,
            "conversation model invocation failure retains assistant message"
        )

        try Expect.equal(
            invocationFailure.kind,
            AgentRunFailure.Kind.model_invocation_failed,
            "conversation model invocation failure kind"
        )
        try Expect.equal(
            invocationFailureRequests.count,
            1,
            "conversation model invocation failure records one attempted request"
        )
        try Expect.contains(
            invocationFailure.message,
            "Scripted model has no stream batch left.",
            "streaming model failure preserves adapter message"
        )
        try Expect.equal(
            invocationFailureResult.events.contains {
                $0.kind == .model_stream_failed
            },
            true,
            "streaming model failure records model stream failure event"
        )
        try Expect.equal(
            invocationFailureResult.events.last?.kind,
            Optional(AgentRunEvent.Kind.run_failed),
            "streaming model failure records terminal run event"
        )
        try Expect.equal(
            invocationFailureRun.state,
            AgenticHostConsoleRunState.failed,
            "conversation model invocation failure projects failed run"
        )
        try Expect.equal(
            invocationFailureAssistant.attachments,
            [
                AgenticConversationAttachmentPresentation.run(
                    runID: invocationFailureResult.sessionID
                ),
            ],
            "conversation model invocation failure retains run attachment"
        )
        try Expect.contains(
            invocationFailureInput ?? "",
            "Trigger a model invocation failure.",
            "conversation model invocation failure retains input"
        )
        try Expect.contains(
            invocationFailureOutput ?? "",
            "model_invocation_failed",
            "conversation model invocation failure retains encoded output"
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
            .field(
                "buffered_model_failure",
                bufferedFailureResult.failure?.kind.rawValue ?? "missing"
            ),
            .field(
                "streaming_model_failure",
                invocationFailure.kind.rawValue
            ),
            AdapterRuntimeFlowDiagnostics.events(
                result.events
            ),
        ]
    }

    static func runLiveStateObservation() async throws -> [TestFlowDiagnostic] {
        let response = AgentResponse(
            message: .init(
                role: .assistant,
                text: "live state ok"
            ),
            stopReason: .end_turn
        )
        let adapter = AdapterFlowScriptedModelAdapter(
            streamBatches: [
                [
                    .messagedelta(
                        .text("live ")
                    ),
                    .messagedelta(
                        .text("state ok")
                    ),
                    .completed(
                        response
                    ),
                ],
            ]
        )
        let sink = ConversationRuntimeStateSink()
        let runner = AgentRunner(
            adapter: adapter,
            configuration: .init(
                maximumIterations: 1,
                responseDelivery: .stream
            ),
            stateSinks: [
                sink,
            ]
        )
        let result = try await runner.run(
            AgentRequest(
                messages: [
                    .init(
                        role: .user,
                        text: "stream a response"
                    ),
                ]
            ),
            sessionID: "conversation-live-state"
        )
        let snapshots = await sink.snapshots()
        let startedAt: Date = try Expect.notNil(
            snapshots.first?.startedAt,
            "live state start time"
        )
        let receivingSnapshot: AgentRunStateSnapshot = try Expect.notNil(
            snapshots.first(where: { snapshot in
                snapshot.phase == .receiving_model_response
            }),
            "live receiving snapshot"
        )
        let liveProjection = AgenticConversationRunProjection.project(
            receivingSnapshot,
            title: "live conversation run"
        )

        try Expect.equal(
            liveProjection.run.state,
            AgenticHostConsoleRunState.active,
            "live projection remains active while receiving model response"
        )
        try Expect.equal(
            liveProjection.run.steps.isEmpty,
            true,
            "live model response does not synthesize a completed step before tool use"
        )

        try Expect.equal(
            snapshots.first?.phase,
            Optional(AgentHistoryPhase.ready_for_model),
            "live state begins ready for model"
        )
        try Expect.equal(
            snapshots.contains { snapshot in
                snapshot.phase == .receiving_model_response
            },
            true,
            "live state exposes receiving phase"
        )
        try Expect.equal(
            snapshots.contains { snapshot in
                snapshot.partialResponse?.message.content.text == "live "
            },
            true,
            "live state exposes partial assistant text before completion"
        )
        try Expect.equal(
            snapshots.allSatisfy { snapshot in
                snapshot.startedAt == startedAt
            },
            true,
            "live state preserves stable start time"
        )
        try Expect.equal(
            snapshots.last?.phase,
            Optional(AgentHistoryPhase.completed),
            "live state publishes completed phase"
        )
        try Expect.equal(
            result.response?.message.content.text,
            "live state ok",
            "live state observation does not alter the run result"
        )

        return [
            .field(
                "snapshots",
                String(snapshots.count)
            ),
            .field(
                "final_phase",
                snapshots.last?.phase.rawValue ?? "missing"
            ),
        ]
    }
}
