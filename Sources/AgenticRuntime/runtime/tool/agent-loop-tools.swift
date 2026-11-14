import Agentic
import AgenticIO
import AgenticStandard
import Workspace
import Foundation
import Primitives

extension AgentLoop {
    func functionCalls(
        in message: Message
    ) -> [FunctionCall] {
        message.content.blocks.compactMap { block in
            guard case .call(let value) = block else {
                return nil
            }

            return value
        }
    }

    func appendToolResultBlock(
        _ block: MessageContentBlock,
        to state: inout AgentExecutor.State
    ) {
        if configuration.appendToolResultsAsMessages {
            state.messages.append(
                Message(
                    role: .tool,
                    content: .init(
                        blocks: [block]
                    )
                )
            )
            return
        }

        if let last = state.messages.last,
           last.role == .tool {
            var updated = last
            updated.content.blocks.append(
                block
            )
            state.messages.removeLast()
            state.messages.append(
                updated
            )
            return
        }

        state.messages.append(
            Message(
                role: .tool,
                content: .init(
                    blocks: [block]
                )
            )
        )
    }

    func resolveApprovalDecision(
        for preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) async throws -> ApprovalDecision {
        guard let approvalHandler = tooling.approvalHandler else {
            return requirement.decision
        }

        return try await approvalHandler.decide(
            on: preflight,
            requirement: requirement
        )
    }

    func executeApprovedCall(
        _ pendingApproval: PendingApproval,
        advertisedTools: [ToolIdentifier]?
    ) async throws -> ToolExecution.Result {
        let available = await capabilityState.available
        guard advertisedTools?.contains(ToolIdentifier(pendingApproval.functionCall.name)) == true,
              available.tools.contains(ToolIdentifier(pendingApproval.functionCall.name))
        else {
            throw FunctionCallResolutionError.toolNotVisible(
                ToolIdentifier(pendingApproval.functionCall.name)
            )
        }

        let invoker = ToolExecutor(
            registry: (await currentTools()),
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery
        )
        let invocation = try (await currentTools()).invocation(
            for: pendingApproval.functionCall
        )
        // The approved plan is the one captured by the checkpoint, not a
        // freshly generated preflight/plan with a different identity.
        let requirement = invoker.policy.evaluate(pendingApproval.preflight)
        guard requirement == pendingApproval.requirement else {
            throw RuntimeApprovedToolInvocationError.stale_preflight
        }
        let freshReview = ToolInvocation.Review(
            invocation: invocation,
            preflight: pendingApproval.preflight,
            requirement: pendingApproval.requirement,
            preparedOperation: pendingApproval.preparedOperation
        )

        return try await executeApprovedToolReview(
            freshReview
        )
    }

    func executeApprovedToolReview(
        _ review: ToolInvocation.Review
    ) async throws -> ToolExecution.Result {
        let available = await capabilityState.available
        guard available.tools.contains(review.invocation.tool) else {
            throw FunctionCallResolutionError.toolNotVisible(review.invocation.tool)
        }
        let invoker = ToolExecutor(
            registry: (await currentTools()),
            policy: configuration.toolExecutionPolicy,
            recovery: configuration.recovery,
            observationHandler: { observation in
                try? await self.record(
                    .tool_observation(observation)
                )
            }
        )
        let invocation = try await invoker.invoke(
            review,
            context: await makeToolContext(),
            approvalHandler: RuntimeResolvedToolApprovalHandler(
                decision: .approved
            )
        )

        guard case .executed(let execution) = invocation.outcome else {
            throw RuntimeApprovedToolInvocationError.not_executed
        }

        return execution
    }

    func makeToolContext() async -> ToolContext {
        ToolContext(
            workspace: tooling.workspace,
            catalog: await inventory.catalog(),
            capabilities: capabilityState,
            inspections: await inventory.capabilityInspections(),
            services: tooling.services.revealing(capabilityState)
        )
    }

    func makeDeniedToolResult(
        for functionCall: FunctionCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) throws -> FunctionCall.Response {
        let payload = ToolDenialPayload(
            kind: "tool_denied",
            callID: functionCall.id,
            toolName: functionCall.name,
            requirement: requirement.rawValue,
            summary: preflight.summary
        )

        return FunctionCall.Response(
            call: functionCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: true
        )
    }

    func makeSkippedToolResult(
        for functionCall: FunctionCall,
        summary: String = "Skipped explicitly by the operator."
    ) throws -> FunctionCall.Response {
        let payload = ToolSkipPayload(
            kind: "tool_skipped",
            callID: functionCall.id,
            toolName: functionCall.name,
            summary: summary
        )

        return FunctionCall.Response(
            call: functionCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: false
        )
    }

    func makeToolErrorResult(
        for functionCall: FunctionCall,
        error: Error
    ) throws -> FunctionCall.Response {
        let payload = ToolErrorPayload(
            kind: "tool_error",
            callID: functionCall.id,
            toolName: functionCall.name,
            message: localizedDescription(for: error)
        )

        return FunctionCall.Response(
            call: functionCall.reference,
            output: try JSONCoding.default.value(payload),
            isError: true
        )
    }

    func localizedDescription(
        for error: Error
    ) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(
            describing: error
        )
    }
}

private enum RuntimeApprovedToolInvocationError: Error, Sendable {
    case stale_preflight
    case not_executed
}

private struct RuntimeResolvedToolApprovalHandler:
    ToolApprovalHandler,
    Sendable
{
    let decision: ApprovalDecision

    func decide(
        on _: ToolPreflight,
        requirement _: ApprovalRequirement
    ) async throws -> ApprovalDecision {
        decision
    }
}

extension ToolServices {
    /// These services plus the owner's reveal grant over `state`.
    func revealing(
        _ state: AgentCapabilityState
    ) -> ToolServices {
        (try? inserting(CapabilityReveal(state))) ?? self
    }
}
