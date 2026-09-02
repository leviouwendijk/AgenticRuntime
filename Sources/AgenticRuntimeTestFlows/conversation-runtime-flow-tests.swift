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
            skillIDs: []
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
}
