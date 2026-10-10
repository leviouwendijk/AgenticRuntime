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
            "usage-absorption-cost-tracker",
            tags: ["runtime", "usage", "pricing", "tokens", "migration"]
        ) {
            try AgenticProgramRuntimeFlowTesting.runUsageAbsorptionCostTracker()
        },
        TestFlow(
            "instruction-selection",
            tags: ["runtime", "instructions", "catalog", "selection"]
        ) {
            try AgenticProgramRuntimeFlowTesting.runInstructionSelection()
        },
        TestFlow(
            "context-allocator",
            tags: ["runtime", "context", "allocator", "working-set", "budget"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runContextAllocator()
        },
        TestFlow(
            "context-inference-preparation",
            tags: ["runtime", "context", "inference", "budget", "token-estimation"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runContextInferencePreparation()
        },
        TestFlow(
            "context-evidence-resolution",
            tags: ["runtime", "context", "evidence", "session", "authorization"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runContextEvidenceResolution()
        },
        TestFlow(
            "context-invocation-audit",
            tags: ["runtime", "context", "inference", "audit", "usage"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runContextInvocationAudit()
        },
        TestFlow(
            "context-allocator-roles",
            tags: ["runtime", "context", "allocator", "roles", "models"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runContextAllocatorRoles()
        },
        TestFlow(
            "context-dynamic-mode",
            tags: ["runtime", "context", "dynamic", "history", "checkpoint"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runContextDynamicMode()
        },
        TestFlow("tool-observation-history", tags: ["runtime", "observations", "persistence"]) {
            try AgenticProgramRuntimeFlowTesting.runToolObservationHistory()
        },
        TestFlow(
            "agent-capability-state",
            tags: [
                "agentic-runtime",
                "agent",
                "capabilities",
                "availability",
                "visibility",
                "discovery",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runAgentCapabilityState()
        },
        TestFlow(
            "agent-realization",
            tags: [
                "agentic-runtime",
                "agent",
                "realization",
                "capabilities",
                "installation",
                "model-selection",
                "visibility",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runAgentRealization()
        },
        TestFlow(
            "inference-installation",
            tags: ["agentic-runtime", "inference", "installation", "execution", "realization"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runInferenceInstallation()
        },
        TestFlow(
            "agent-owned-capability-inventory-live-mutation",
            tags: ["agentic-runtime", "agent", "capabilities", "live", "installation"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runLiveCapabilityInventory()
        },
        TestFlow(
            "capability-dispatch",
            tags: ["agentic-runtime", "capabilities", "inference", "authorization"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runCapabilityDispatch()
        },
        TestFlow(
            "capability-contract-alignment",
            tags: ["agentic-runtime", "capabilities", "typed", "contract"]
        ) {
            try AgenticProgramRuntimeFlowTesting.runCapabilityContractAlignment()
        },
        TestFlow(
            "model-capability-projection",
            tags: ["agentic-runtime", "capabilities", "projection", "model"]
        ) {
            try await AgenticProgramRuntimeFlowTesting.runModelCapabilityProjection()
        },
        TestFlow(
            "runtime-diagnostics",
            tags: [
                "agentic-runtime",
                "diagnostics",
                "capabilities",
                "installation",
                "visibility",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runRuntimeDiagnostics()
        },
        TestFlow(
            "agent-invocation",
            tags: [
                "agentic-runtime",
                "agent",
                "invocation",
                "model-selection",
                "capabilities",
                "visibility",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runAgentInvocation()
        },
        TestFlow(
            "agent-authored-visible-capabilities-survive-runtime-launch",
            tags: [
                "agentic-runtime",
                "agent",
                "mode",
                "capabilities",
                "visibility",
                "launch",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runAuthoredVisibleCapabilitiesSurviveLaunch()
        },
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
            "application-installation-composition",
            tags: [
                "agentic-runtime",
                "application",
                "installation",
                "composition",
                "tool",
                "program",
                "agent",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runApplicationInstallationComposition()
        },
        TestFlow(
            "application-catalog-installation",
            tags: [
                "agentic-runtime",
                "application",
                "installation",
                "catalog",
                "domain",
                "linker",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runApplicationCatalogInstallation()
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
        TestFlow(
            "malformed-clarify-tool-input-recovery",
            tags: [
                "agentic-runtime",
                "tool",
                "decode",
                "recovery",
                "user-input",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runMalformedClarifyToolInputRecovery()
        },
        TestFlow(
            "agent-run-limit-stop",
            tags: [
                "agentic-runtime",
                "run-limit",
                "suspension",
                "interruption",
                "persistence",
            ]
        ) {
            try await AgenticProgramRuntimeFlowTesting
                .runAgentRunLimitStop()
        },
    ]
}

enum AgenticProgramRuntimeFlowTesting {}
