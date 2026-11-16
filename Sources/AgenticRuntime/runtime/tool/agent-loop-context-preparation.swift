import Agentic
import AgenticContext

extension AgentLoop {
    func prepareModelRequest(
        from request: AgentRequest,
        checkpoint: AgentExecutor.Checkpoint
    ) async throws -> (request: AgentRequest, preparation: Context.InferencePreparation?) {
        var prepared = request
        var dynamic: Context.InferencePreparation?
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
                        + configuration.contextPolicy.reservedOutputTokens,
                compactions: await contextServices?.compactions?.compactions ?? []
            )
            if let audit = contextServices?.audit {
                try await audit.record(
                    Context.InferenceAuditFingerprint.prepared(preparation)
                )
            }
            prepared = preparation.request
            dynamic = preparation
        }
        for harnessExtension in extensions {
            prepared = try await harnessExtension.prepare(
                request: prepared,
                state: checkpoint.state
            )
        }
        return (prepared, dynamic)
    }
}
