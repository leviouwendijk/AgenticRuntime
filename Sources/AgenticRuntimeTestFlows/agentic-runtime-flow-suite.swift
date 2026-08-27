import TestFlows

enum AgenticRuntimeFlowSuite: TestFlowRegistry {
    static let title = "AgenticRuntime flow tests"

    static let flows: [TestFlow] = [
        TestFlow(
            "application-realization",
            tags: [
                "agentic-runtime",
                "application",
                "realization",
            ]
        ) {
            try await AgenticRuntimeFlowTesting
                .runApplicationRealization()
        },
        TestFlow(
            "host-parity",
            tags: [
                "agentic-runtime",
                "host",
                "parity",
            ]
        ) {
            try await AgenticRuntimeFlowTesting
                .runHostParity()
        },
    ]
}
