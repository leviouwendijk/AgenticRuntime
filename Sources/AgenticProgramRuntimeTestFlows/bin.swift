import TestFlows

@main
enum AgenticProgramRuntimeFlowTestMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: AgenticProgramRuntimeFlowSuite.self
        )
    }
}

enum AgenticProgramRuntimeFlowSuite: TestFlowRegistry {
    static let title = "Agentic program runtime flow tests"

    static let flows: [TestFlow] = [
        TestFlow(
            "program-execution-record",
            tags: [
                "agentic-runtime",
                "program",
                "execution",
                "trace",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramExecutionRecord()
        },
        TestFlow(
            "program-execution-failure-record",
            tags: [
                "agentic-runtime",
                "program",
                "execution",
                "failure",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramExecutionFailureRecord()
        },
        TestFlow(
            "program-inference-execution-record",
            tags: [
                "agentic-runtime",
                "program",
                "inference",
                "realization",
                "usage",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramInferenceExecutionRecord()
        },
    ]
}

enum AgenticProgramRuntimeFlowTesting {}
