import Agentic
import AgenticIntents

extension AgentLoop {
    /// Stores a call that needs review as an intent and lets the run go on
    /// without it. Nil when the host installed no `Intents.Manager` or the
    /// call prepares no operation; the caller then suspends instead, so a
    /// deferral never lets a call skip review.
    func deferForReview(
        _ review: ToolInvocation.Review,
        for functionCall: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> CallOutcome? {
        guard let manager = try? tooling.services.require(Intents.Manager.self),
              let operation = review.preparedOperation
        else {
            return nil
        }

        let intent = try await manager.create(
            .init(
                sessionID: checkpoint.id,
                invocation: .init(
                    review: review,
                    operation: operation
                ),
                metadata: [
                    "call_id": functionCall.id,
                ]
            )
        )
        let summary = "deferred as intent \(intent.id)"

        try await appendToolResult(
            FunctionCall.Response(
                call: functionCall.reference,
                output: .object([
                    "kind": .string("tool_deferred"),
                    "callID": .string(functionCall.id),
                    "toolName": .string(functionCall.name),
                    "intent": .string(intent.id.raw),
                    "message": .string(
                        "Stored as intent \(intent.id) for review; it has not run. "
                            + "Continue with work that doesn't depend on it."
                    ),
                ]),
                isError: false
            ),
            for: functionCall,
            disposition: .deferred_for_review,
            to: &checkpoint,
            summary: summary,
            eventKind: .tool_deferred
        )
        try await saveCheckpoint(&checkpoint)
        return .next
    }

    /// Suspends the run until a person decides on the call.
    func suspendForApproval(
        _ review: ToolInvocation.Review,
        for functionCall: FunctionCall,
        note: String? = nil,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> CallOutcome {
        suspendToolBatch(
            for: functionCall,
            disposition: .suspended_for_approval,
            on: &checkpoint
        )
        checkpoint.suspend(
            .approval(
                PendingApproval(
                    functionCall: functionCall,
                    preflight: review.preflight,
                    requirement: review.requirement,
                    preparedOperation: review.preparedOperation
                )
            )
        )
        try await appendRunEvent(
            .init(
                kind: .pending_approval,
                iteration: checkpoint.state.iteration,
                callID: functionCall.id,
                toolName: functionCall.name,
                summary: note.map { "\(review.preflight.summary) (\($0))" } ?? review.preflight.summary
            ),
            to: &checkpoint
        )
        try await saveCheckpoint(&checkpoint)
        return .stop(try suspendedResult(from: checkpoint))
    }
}
