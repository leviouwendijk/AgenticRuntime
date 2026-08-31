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
