import Agentic
import AgenticContext

extension AgentLoop {
    func prepareModelRequest(
        from request: AgentRequest,
        checkpoint: AgentExecutor.Checkpoint
    ) async throws -> (request: AgentRequest, history: Context.HistorySelection?) {
        var prepared = request
        var history: Context.HistorySelection?
        if configuration.contextMode == .dynamic {
            guard let allocator = contextAllocator else {
                throw ContextExecutionError.requiresDynamicMode
            }
            let preparation = try await allocator.prepareDynamic(
                request: prepared,
                for: checkpoint.id,
                using: contextServices?.resolver ?? Context.UnmountedResolver(),
                modelContextLimit: contextServices?.modelContextLimit
                    ?? configuration.contextPolicy.maximumInputTokens
                        + configuration.contextPolicy.reservedOutputTokens
            )
            if let audit = contextServices?.audit {
                try await audit.record(
                    Context.InferenceAuditFingerprint.prepared(preparation)
                )
            }
            prepared = preparation.request
            history = preparation.history
        }
        for harnessExtension in extensions {
            prepared = try await harnessExtension.prepare(
                request: prepared,
                state: checkpoint.state
            )
        }
        return (prepared, history)
    }
}
