import Agentic
import AgenticExecution
import AgenticRuntime
import AgenticTools
import Primitives
import TestFlows

enum AgenticRuntimeToolExposureFlowTesting {
    static func runExplicitEnforcement() async throws -> [TestFlowDiagnostic] {
        let store = AdapterFlowScratchpadStore()
        let hiddenTool = AdapterFlowScratchpadTool(
            store: store
        )
        let hiddenCall = AgentToolCall(
            id: "runtime-hidden-tool-call",
            name: AdapterFlowScratchpadTool.identifier.rawValue,
            input: try JSONToolBridge.encode(
                AdapterFlowScratchpadPutInput(
                    text: "must not execute"
                )
            )
        )
        let firstResponse = AgentResponse(
            message: .init(
                role: .assistant,
                content: .init(
                    blocks: [
                        .tool_call(
                            hiddenCall
                        ),
                    ]
                )
            ),
            stopReason: .tool_use
        )
        let finalResponse = AgentResponse(
            message: .init(
                role: .assistant,
                text: "hidden call rejected"
            ),
            stopReason: .end_turn
        )
        let adapter = AdapterFlowScriptedModelAdapter(
            streamBatches: [
                [
                    .toolcall(
                        hiddenCall
                    ),
                    .completed(
                        firstResponse
                    ),
                ],
                [
                    .completed(
                        finalResponse
                    ),
                ],
            ]
        )
        let runner = AgentRunner(
            adapter: adapter,
            configuration: .init(
                maximumIterations: 2,
                toolExposure: .explicit(
                    [
                        AdapterFlowEchoTool.identifier,
                    ]
                ),
                responseDelivery: .stream
            ),
            toolRegistry: .init(
                tools: [
                    AdapterFlowEchoTool(),
                    hiddenTool,
                ]
            )
        )

        let result = try await runner.run(
            AgentRequest(
                model: "scripted",
                messages: [
                    .init(
                        role: .user,
                        text: "Attempt the hidden tool."
                    ),
                ]
            ),
            sessionID: "runtime-tool-exposure-explicit"
        )
        let requests = await adapter.recordedRequests()
        let values = await store.all()
        let toolResults = requests
            .flatMap(
                \.messages
            )
            .flatMap(
                \.content.blocks
            )
            .compactMap { block -> AgentToolResult? in
                guard case .tool_result(let result) = block else {
                    return nil
                }

                return result
            }

        try Expect.equal(
            requests.count,
            2,
            "explicit exposure model request count"
        )

        for request in requests {
            try Expect.equal(
                request.tools.map(
                    \.name
                ),
                [
                    AdapterFlowEchoTool.identifier.rawValue,
                ],
                "explicit exposure advertises only the selected model-facing tool"
            )
        }

        try Expect.isEmpty(
            values,
            "hidden mutating tool never executes"
        )

        let hiddenResult = try Expect.notNil(
            toolResults.last,
            "hidden-call error result"
        )

        try Expect.equal(
            hiddenResult.isError,
            true,
            "hidden model call becomes an error result"
        )

        try Expect.contains(
            String(
                describing: hiddenResult.output
            ),
            "not exposed",
            "hidden-call error explains exposure rejection"
        )

        return [
            .field(
                "advertised",
                requests.first?.tools.map(\.name).joined(separator: ",")
                    ?? "<none>"
            ),
            .field(
                "hidden_executed",
                String(!values.isEmpty)
            ),
        ]
    }

    static func runSkillSeededDiscovery() async throws -> [TestFlowDiagnostic] {
        let store = AdapterFlowScratchpadStore()
        let skill = AgentSkill(
            identifier: "runtime-exposure-seed",
            name: "Runtime exposure seed",
            summary: "Seed the echo tool.",
            body: "Use the echo tool.",
            metadata: .init(
                tools: .init(
                    required: [
                        .tool(
                            AdapterFlowEchoTool.identifier
                        ),
                    ]
                )
            )
        )
        let finalResponse = AgentResponse(
            message: .init(
                role: .assistant,
                text: "seeded"
            ),
            stopReason: .end_turn
        )
        let adapter = AdapterFlowScriptedModelAdapter(
            streamBatches: [
                [
                    .completed(
                        finalResponse
                    ),
                ],
            ]
        )
        let runner = AgentRunner(
            adapter: adapter,
            configuration: .init(
                maximumIterations: 1,
                toolExposure: .skillSeeded(
                    [
                        skill,
                    ]
                ),
                responseDelivery: .stream
            ),
            toolRegistry: .init(
                tools: [
                    AdapterFlowEchoTool(),
                    AdapterFlowScratchpadTool(
                        store: store
                    ),
                ]
            )
        )

        _ = try await runner.run(
            AgentRequest(
                model: "scripted",
                messages: [
                    .init(
                        role: .user,
                        text: "Inspect the seeded tool surface."
                    ),
                ]
            ),
            sessionID: "runtime-tool-exposure-skill-seed"
        )

        let requests = await adapter.recordedRequests()
        let advertised = try Expect.notNil(
            requests.first,
            "skill-seeded request"
        ).tools.map(
            \.name
        )

        try Expect.equal(
            advertised,
            [
                AdapterFlowEchoTool.identifier.rawValue,
                FindToolsTool.identifier.rawValue,
            ],
            "skill-seeded discovery exposes skill tools plus find_tools"
        )

        return [
            .field(
                "advertised",
                advertised.joined(separator: ",")
            ),
        ]
    }
}
