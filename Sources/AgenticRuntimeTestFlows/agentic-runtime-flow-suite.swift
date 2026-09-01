import TestFlows
import AgenticIO

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
        TestFlow(
            "workspace-resource-resolution",
            tags: [
                "agentic-runtime",
                "resource",
                "resolution",
                "workspace",
            ]
        ) {
            try await AgenticRuntimeFlowTesting
                .runWorkspaceResourceResolution()
        },
        TestFlow(
            "host-output-documents",
            tags: [
                "agentic-runtime",
                "host",
                "projection",
                "stdout",
                "stderr",
            ]
        ) {
            try AgenticRuntimeHostProjectionFlowTesting
                .runOutputDocuments()
        },
        TestFlow(
            "host-empty-output-documents",
            tags: [
                "agentic-runtime",
                "host",
                "projection",
                "stdout",
                "stderr",
                "empty",
            ]
        ) {
            try AgenticRuntimeHostProjectionFlowTesting
                .runEmptyOutputDocuments()
        },
        TestFlow(
            "host-ready-documents",
            tags: [
                "agentic-runtime",
                "host",
                "pending",
                "preflight",
                "diff",
                "safety",
            ]
        ) {
            try await AgenticRuntimePendingDocumentFlowTesting
                .runReadyDocuments()
        },
        TestFlow(
            "host-review-boundary",
            tags: [
                "agentic-runtime",
                "host",
                "approval",
                "preflight",
                "diff",
                "single-step",
                "safety",
                "end-to-end",
            ]
        ) {
            try await AgenticRuntimePendingDocumentFlowTesting
                .runReviewBoundary()
        },
        TestFlow(
            "host-status-diagnostics",
            tags: [
                "agentic-runtime",
                "host",
                "status",
                "diagnostic",
                "persistence",
            ]
        ) {
            try await AgenticRuntimeHostStatusFlowTesting
                .runPersistentFailureStatus()
        },
        TestFlow(
            "tool-plan-deferred-pause",
            tags: [
                "agentic-runtime",
                "tool-plan",
                "execution-policy",
                "continuous",
                "pause",
                "boundary",
            ]
        ) {
            try await AgenticRuntimeToolPlanFlowTesting
                .runDeferredPause()
        },
        TestFlow(
            "tool-plan-single-step-resolution-policy",
            tags: [
                "agentic-runtime",
                "tool-plan",
                "execution-policy",
                "single-step",
                "recovery",
                "boundary",
            ]
        ) {
            try await AgenticRuntimeToolPlanFlowTesting
                .runSingleStepResolutionPolicy()
        },
        TestFlow(
            "tool-plan-recovery-retry",
            tags: [
                "agentic-runtime",
                "tool-plan",
                "recovery",
                "retry",
                "memory",
            ]
        ) {
            try await AgenticRuntimeToolPlanFlowTesting
                .runRecoveryThenRetry()
        },
        TestFlow(
            "tool-plan-recovery-skip",
            tags: [
                "agentic-runtime",
                "tool-plan",
                "recovery",
                "skip",
                "memory",
            ]
        ) {
            try await AgenticRuntimeToolPlanFlowTesting
                .runRecoveryThenSkip()
        },
        TestFlow(
            "tool-plan-recovery-hierarchy",
            tags: [
                "agentic-runtime",
                "tool-plan",
                "recovery",
                "hierarchy",
                "gating",
            ]
        ) {
            try await AgenticRuntimeToolPlanFlowTesting
                .runRecoveryHierarchyAndGating()
        },
    ]
}
