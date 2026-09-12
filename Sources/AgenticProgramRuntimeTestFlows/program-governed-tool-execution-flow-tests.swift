import Agentic
import AgenticExecution
import AgenticPrograms
import AgenticRuntime
import Primitives
import Schema
import Macros
import TestFlows

private actor GovernedProgramToolProbe {
    private var executionCount = 0

    func record() {
        executionCount += 1
    }

    func count() -> Int {
        executionCount
    }
}

@JSONSchema
private struct GovernedProgramToolInput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct GovernedProgramToolOutput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
    let sessionID: String?
    let source: String?
}

private struct GovernedProgramInput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct GovernedProgram:
    AgentProgram
{
    typealias Input = GovernedProgramInput
    typealias Output = GovernedProgramToolOutput

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.governed_program",
        title: "Governed Program fixture",
        summary: "Proves Program tool requests traverse AgenticExecution governance."
    )

    func run(
        _ input: Input,
        in context: AgentProgramContext
    ) async throws -> Output {
        try await context.invoke(
            AgentToolIdentifier(
                "fixture.governed_program_tool"
            ),
            input: GovernedProgramToolInput(
                value: input.value
            ),
            as: GovernedProgramToolOutput.self
        )
    }
}

private struct GovernedProgramTool:
    AgentTool
{
    typealias Input = GovernedProgramToolInput
    typealias Output = GovernedProgramToolOutput

    let identifier: AgentToolIdentifier =
        "fixture.governed_program_tool"
    let description =
        "Records execution only after the canonical ToolInvoker governance path permits it."
    let risk: ActionRisk
    let probe: GovernedProgramToolProbe

    func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        _ = input

        return ToolPreflight(
            toolName: identifier.rawValue,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            summary: description
        )
    }

    func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        await probe.record()

        return GovernedProgramToolOutput(
            value: "executed:\(input.value)",
            sessionID: context.sessionID,
            source: context.metadata["source"]
        )
    }
}

private struct GovernedProgramApprovalHandler:
    ToolApprovalHandler
{
    let decision: ApprovalDecision

    func decide(
        on _: ToolPreflight,
        requirement _: ApprovalRequirement
    ) async throws -> ApprovalDecision {
        decision
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runProgramGovernedToolExecution()
        async throws
        -> [TestFlowDiagnostic]
    {
        let observeProbe = GovernedProgramToolProbe()
        let observeRegistry = try ToolRegistry {
            GovernedProgramTool(
                risk: .observe,
                probe: observeProbe
            )
        }
        let observeRunner = AgentProgramRunner(
            services: .init(
                program: .init(
                    tools: GovernedAgentProgramToolExecutor(
                        registry: observeRegistry,
                        policy: .init(
                            autonomyMode: .auto_observe
                        ),
                        context: .init(
                            sessionID: "program-governance-observe",
                            metadata: [
                                "source": "agent_program",
                            ]
                        )
                    )
                )
            )
        )
        let observeExecution = try await observeRunner.execute(
            GovernedProgram(),
            input: .init(
                value: "observe"
            )
        )
        let observeCount = await observeProbe.count()

        try Expect.equal(
            observeExecution.record.outcome,
            .succeeded,
            "observe Program tool succeeds through ToolInvoker governance"
        )
        try Expect.equal(
            observeExecution.output?.value,
            "executed:observe",
            "observe Program receives governed semantic tool output"
        )
        try Expect.equal(
            observeExecution.output?.sessionID,
            "program-governance-observe",
            "Program tool execution preserves Runtime execution context"
        )
        try Expect.equal(
            observeExecution.output?.source,
            "agent_program",
            "Program tool execution preserves Program provenance metadata"
        )
        try Expect.equal(
            observeCount,
            1,
            "observe Program tool executes exactly once"
        )
        try Expect.equal(
            observeExecution.record.steps.count,
            1,
            "governed Program tool remains one recorded Program step"
        )
        try Expect.equal(
            observeExecution.record.steps[0].failure == nil,
            true,
            "successful governed Program tool step has no failure"
        )

        let reviewProbe = GovernedProgramToolProbe()
        let reviewRegistry = try ToolRegistry {
            GovernedProgramTool(
                risk: .boundedmutate,
                probe: reviewProbe
            )
        }
        let reviewRunner = AgentProgramRunner(
            services: .init(
                program: .init(
                    tools: GovernedAgentProgramToolExecutor(
                        registry: reviewRegistry,
                        policy: .init(
                            autonomyMode: .auto_observe
                        )
                    )
                )
            )
        )
        let reviewExecution = try await reviewRunner.execute(
            GovernedProgram(),
            input: .init(
                value: "review"
            ),
            sessionID: "fixture-governed-program-review"
        )
        let reviewCount = await reviewProbe.count()

        try Expect.equal(
            reviewExecution.record.outcome,
            .suspended,
            "approval-gated Program tool suspends when no approval handler is supplied"
        )
        try Expect.equal(
            reviewExecution.output == nil,
            true,
            "suspended Program tool produces no semantic output"
        )
        try Expect.equal(
            reviewCount,
            0,
            "approval-gated Program tool does not execute before approval"
        )
        try Expect.equal(
            reviewExecution.record.steps.count,
            1,
            "approval boundary remains visible as one suspended Program tool step"
        )
        try Expect.equal(
            reviewExecution.record.steps[0].failure == nil,
            true,
            "approval suspension is not misclassified as a step failure"
        )
        try Expect.equal(
            reviewExecution.record.steps[0].suspension != nil,
            true,
            "approval-required Program tool step preserves AgentSuspension"
        )
        try Expect.equal(
            reviewExecution.record.failure == nil,
            true,
            "approval suspension is not misclassified as root Program failure"
        )
        try Expect.equal(
            reviewExecution.record.checkpoint != nil,
            true,
            "approval suspension emits a durable Program checkpoint"
        )
        try Expect.equal(
            reviewExecution.interactionRequest?.kind,
            .approval,
            "suspended Program exposes the shared approval interaction request"
        )

        let approvedProbe = GovernedProgramToolProbe()
        let approvedRegistry = try ToolRegistry {
            GovernedProgramTool(
                risk: .boundedmutate,
                probe: approvedProbe
            )
        }
        let approvedRunner = AgentProgramRunner(
            services: .init(
                program: .init(
                    tools: GovernedAgentProgramToolExecutor(
                        registry: approvedRegistry,
                        policy: .init(
                            autonomyMode: .auto_observe
                        ),
                        approvalHandler: GovernedProgramApprovalHandler(
                            decision: .approved
                        )
                    )
                )
            )
        )
        let approvedExecution = try await approvedRunner.execute(
            GovernedProgram(),
            input: .init(
                value: "approved"
            )
        )
        let approvedCount = await approvedProbe.count()

        try Expect.equal(
            approvedExecution.record.outcome,
            .succeeded,
            "approved Program tool succeeds through the same governance path"
        )
        try Expect.equal(
            approvedExecution.output?.value,
            "executed:approved",
            "approved Program receives semantic tool output"
        )
        try Expect.equal(
            approvedCount,
            1,
            "approved Program tool executes exactly once"
        )
        try Expect.equal(
            approvedExecution.record.steps[0].failure == nil,
            true,
            "approved Program tool step records successful execution"
        )

        let deniedProbe = GovernedProgramToolProbe()
        let deniedRegistry = try ToolRegistry {
            GovernedProgramTool(
                risk: .boundedmutate,
                probe: deniedProbe
            )
        }
        let deniedRunner = AgentProgramRunner(
            services: .init(
                program: .init(
                    tools: GovernedAgentProgramToolExecutor(
                        registry: deniedRegistry,
                        policy: .init(
                            autonomyMode: .auto_observe
                        ),
                        approvalHandler: GovernedProgramApprovalHandler(
                            decision: .denied
                        )
                    )
                )
            )
        )
        let deniedExecution = try await deniedRunner.execute(
            GovernedProgram(),
            input: .init(
                value: "denied"
            )
        )
        let deniedCount = await deniedProbe.count()

        try Expect.equal(
            deniedExecution.record.outcome,
            .failed,
            "denied Program tool fails closed"
        )
        try Expect.equal(
            deniedCount,
            0,
            "denied Program tool never executes"
        )
        try Expect.equal(
            deniedExecution.record.failure?.message.contains(
                "was denied"
            ) == true,
            true,
            "denied Program execution preserves governance reason"
        )

        let skippedProbe = GovernedProgramToolProbe()
        let skippedRegistry = try ToolRegistry {
            GovernedProgramTool(
                risk: .boundedmutate,
                probe: skippedProbe
            )
        }
        let skippedRunner = AgentProgramRunner(
            services: .init(
                program: .init(
                    tools: GovernedAgentProgramToolExecutor(
                        registry: skippedRegistry,
                        policy: .init(
                            autonomyMode: .auto_observe
                        ),
                        approvalHandler: GovernedProgramApprovalHandler(
                            decision: .skipped
                        )
                    )
                )
            )
        )
        let skippedExecution = try await skippedRunner.execute(
            GovernedProgram(),
            input: .init(
                value: "skipped"
            )
        )
        let skippedCount = await skippedProbe.count()

        try Expect.equal(
            skippedExecution.record.outcome,
            .failed,
            "skipped Program tool fails closed without executing"
        )
        try Expect.equal(
            skippedCount,
            0,
            "skipped Program tool never executes"
        )
        try Expect.equal(
            skippedExecution.record.failure?.message.contains(
                "was skipped"
            ) == true,
            true,
            "skipped Program execution preserves governance reason"
        )

        let resumedProbe = GovernedProgramToolProbe()
        let resumedRegistry = try ToolRegistry {
            GovernedProgramTool(
                risk: .boundedmutate,
                probe: resumedProbe
            )
        }
        let resumedExecutor = GovernedAgentProgramToolExecutor(
            registry: resumedRegistry,
            policy: .init(
                autonomyMode: .auto_observe
            )
        )
        let resumedInput = try JSONToolBridge.encode(
            GovernedProgramToolInput(
                value: "resumed"
            )
        )
        let resumedCall = AgentToolCall(
            id: "fixture-governed-program-resume",
            name: "fixture.governed_program_tool",
            input: resumedInput
        )
        let resumedReview = try await resumedExecutor.invoker.review(
            resumedCall
        )
        let pendingApproval = PendingApproval(
            toolCall: resumedCall,
            preflight: resumedReview.preflight,
            requirement: resumedReview.requirement
        )
        let resumedOutputValue = try await resumedExecutor.resume(
            pendingApproval: pendingApproval,
            decision: .approved
        )
        let resumedOutput = try JSONToolBridge.decode(
            GovernedProgramToolOutput.self,
            from: resumedOutputValue
        )
        let resumedCount = await resumedProbe.count()

        try Expect.equal(
            resumedReview.requirement,
            .needs_human_review,
            "resume fixture begins from a real approval-gated preflight"
        )
        try Expect.equal(
            resumedOutput.value,
            "executed:resumed",
            "approved Program resume executes the exact pending semantic tool call"
        )
        try Expect.equal(
            resumedCount,
            1,
            "approved Program resume executes the pending tool exactly once"
        )

        return [
            .field(
                "observe_executions",
                String(observeCount)
            ),
            .field(
                "unapproved_executions",
                String(reviewCount)
            ),
            .field(
                "approved_executions",
                String(approvedCount)
            ),
            .field(
                "denied_executions",
                String(deniedCount)
            ),
            .field(
                "skipped_executions",
                String(skippedCount)
            ),
            .field(
                "resumed_executions",
                String(resumedCount)
            ),
        ]
    }
}
