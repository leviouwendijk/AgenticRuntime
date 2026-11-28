import Agentic
import AgenticIO
import AgenticIntents
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
            context: await makeCapabilityContext(),
            approvalHandler: RuntimeResolvedToolApprovalHandler(
                decision: .approved
            )
        )

        guard case .executed(let execution) = invocation.outcome else {
            throw RuntimeApprovedToolInvocationError.not_executed
        }

        return execution
    }

    func makeCapabilityContext() async -> CapabilityContext {
        CapabilityContext(
            workspace: tooling.workspace,
            catalog: await inventory.catalog(),
            capabilities: capabilityState,
            inspections: await inventory.availableInspections(),
            services: await intentServices(
                tooling.services.archivingResults().calling(await served.callForm)
            )
        )
    }

    /// Where the host installed an intents manager, approved intents run
    /// through this run's tools and policy.
    private func intentServices(
        _ services: CapabilityServices
    ) async -> CapabilityServices {
        guard let manager = try? services.require(Intents.Manager.self),
              (try? services.require(Intents.Executor.self)) == nil
        else {
            return services
        }
        let executor = Intents.Executor(
            manager: manager,
            tools: ToolExecutor(
                registry: await currentTools(),
                policy: configuration.toolExecutionPolicy,
                recovery: configuration.recovery
            )
        )
        return (try? services.inserting(executor)) ?? services
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
            summary: preflight.summary,
            warnings: preflight.warnings.isEmpty ? nil : preflight.warnings
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

    /// The model's answer for a failed call, through the session's payload
    /// guard like any other result.
    func makeToolErrorResult(
        for functionCall: FunctionCall,
        error: Error,
        guidance: String? = nil
    ) async throws -> FunctionCall.Response {
        try await .toolError(
            call: functionCall.reference,
            error: error,
            guidance: guidance,
            guard: (try? tooling.services.require(ToolPayloadGuarding.self))?.shield
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

extension CapabilityServices {
    /// These services plus how the model reaches capabilities outside its
    /// definitions.
    func calling(_ form: UndeclaredCallForm) -> CapabilityServices {
        (try? inserting(form)) ?? self
    }

    /// These services plus the result archive over the session log.
    func archivingResults() -> CapabilityServices {
        guard let log = try? require(Run.Log.self) else {
            return self
        }
        // Full results are read back from the session log.
        return (try? inserting(ResultArchive(
            { call in try await log.response(call: call) },
            latest: { tool in try await log.response(tool: tool) },
            recent: { limit in try await log.responses(limit: limit) }
        ))) ?? self
    }
}
