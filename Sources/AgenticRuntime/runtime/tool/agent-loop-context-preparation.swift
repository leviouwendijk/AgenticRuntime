import Agentic

extension AgentLoop {
    func prepareModelRequest(
        from request: AgentRequest,
        checkpoint: AgentRunner.Checkpoint
    ) async throws -> AgentRequest {
        var prepared = request
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
        }
        for harnessExtension in extensions {
            prepared = try await harnessExtension.prepare(
                request: prepared,
                state: checkpoint.state
            )
        }
        return prepared
    }
}
