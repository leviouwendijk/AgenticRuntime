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
            "program-inference-failure-recovery-evidence",
            tags: [
                "agentic-runtime",
                "program",
                "inference",
                "failure",
                "recovery",
                "handling",
                "trace",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramInferenceFailureRecoveryEvidence()
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
        TestFlow(
            "application-gateway-availability",
            tags: [
                "agentic-runtime",
                "application",
                "model",
                "gateway",
                "availability",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runApplicationGatewayAvailability()
        },
        TestFlow(
            "program-governed-tool-execution",
            tags: [
                "agentic-runtime",
                "program",
                "tool",
                "governance",
                "preflight",
                "policy",
                "approval",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramGovernedToolExecution()
        },
        TestFlow(
            "program-user-input-resume",
            tags: [
                "agentic-runtime",
                "program",
                "user-input",
                "suspension",
                "resume",
                "replay",
                "checkpoint",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramUserInputResume()
        },
        TestFlow(
            "program-approval-resume-replay",
            tags: [
                "agentic-runtime",
                "program",
                "approval",
                "suspension",
                "resume",
                "replay",
                "checkpoint",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramApprovalResumeReplay()
        },
        TestFlow(
            "tool-observe-recovery",
            tags: [
                "agentic-runtime",
                "tool",
                "recovery",
                "observe",
                "retry",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runObserveToolRecovery()
        },
        TestFlow(
            "tool-mutation-recovery",
            tags: [
                "agentic-runtime",
                "tool",
                "recovery",
                "mutation",
                "reconciliation",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runMutationToolRecovery()
        },
        TestFlow(
            "tool-classification-propagation",
            tags: [
                "agentic-runtime",
                "tool",
                "recovery",
                "classification",
                "propagation",
                "program",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runToolClassificationPropagation()
        },
        TestFlow(
            "prepared-intent-runtime-execution",
            tags: [
                "agentic-runtime",
                "interaction",
                "prepared-operation",
                "execution",
                "registry",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runPreparedIntentRuntimeExecution()
        },
        TestFlow(
            "workspace-access-lease-activation",
            tags: [
                "agentic-runtime",
                "workspace",
                "path-grant",
                "prepared-operation",
                "lease",
                "turn",
                "session",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runWorkspaceAccessLeaseActivation()
        },
        TestFlow(
            "program-caught-tool-failure-resume",
            tags: [
                "agentic-runtime",
                "program",
                "tool",
                "replay",
                "recovery",
                "user-input",
                "resume",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramCaughtToolFailureResume()
        },
        TestFlow(
            "program-governed-tool-recovery",
            tags: [
                "agentic-runtime",
                "program",
                "tool",
                "governance",
                "recovery",
                "reconciliation",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runProgramGovernedToolRecovery()
        },
    ]
}

enum AgenticProgramRuntimeFlowTesting {}
