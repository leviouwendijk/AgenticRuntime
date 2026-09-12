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
        TestFlow(
            "model-invocation-transport",
            tags: [
                "agentic-runtime",
                "model",
                "invocation",
                "selection",
                "context",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runModelInvocationTransport()
        },
        TestFlow(
            "model-invocation-streaming-completion",
            tags: [
                "agentic-runtime",
                "model",
                "invocation",
                "streaming",
                "completion",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runModelInvocationStreamingCompletion()
        },
        TestFlow(
            "runtime-services-composition",
            tags: [
                "agentic-runtime",
                "services",
                "model",
                "program",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runRuntimeServicesComposition()
        },
        TestFlow(
            "mode-model-selection-propagation",
            tags: [
                "agentic-runtime",
                "mode",
                "model",
                "selection",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runModeModelSelectionPropagation()
        },
        TestFlow(
            "runtime-services-recording-propagation",
            tags: [
                "agentic-runtime",
                "services",
                "recording",
                "events",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runRuntimeServicesRecordingPropagation()
        },
        TestFlow(
            "application-program-installation",
            tags: [
                "agentic-runtime",
                "application",
                "program",
                "registry",
                "execution",
                "realization",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runApplicationProgramInstallation()
        },
    ]
}

enum AgenticProgramRuntimeFlowTesting {}
