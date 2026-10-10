import Agentic

public extension Context {
    /// Opt-in harness bridge, running after model-facing tool projection and
    /// before the model invocation. A fresh Frame is prepared for each call.
    /// Nothing here mutates AgentRunner's canonical checkpoint messages.
    actor InferenceExtension: AgentHarnessExtension {
        public let allocator: Allocator
        public let workingSetID: String
        public let resolver: any RecordResolving
        public let modelContextLimit: Int
        public let delivery: InferenceDelivery
        public let audit: (any InferenceAuditRecording)?
        private var mostRecent: InferencePreparation?

        public init(
            allocator: Allocator,
            workingSetID: String,
            resolver: any RecordResolving,
            modelContextLimit: Int,
            delivery: InferenceDelivery = .supplement,
            audit: (any InferenceAuditRecording)? = nil
        ) {
            self.allocator = allocator
            self.workingSetID = workingSetID
            self.resolver = resolver
            self.modelContextLimit = modelContextLimit
            self.delivery = delivery
            self.audit = audit
        }

        public func prepare(
            request: AgentRequest,
            state: AgentRunner.State
        ) async throws -> AgentRequest {
            mostRecent = nil
            let frame = try await allocator.prepareFrame(
                for: workingSetID,
                using: resolver,
                modelContextLimit: modelContextLimit
            )
            let maximum = max(
                0,
                min(allocator.policy.maximumInputTokens,
                    modelContextLimit - allocator.policy.reservedOutputTokens)
            )
            let preparation = try InferencePreparer.prepare(
                request: request,
                frame: frame,
                delivery: delivery,
                maximumInputTokens: maximum
            )
            if let audit {
                try await audit.record(
                    InferenceAuditFingerprint.prepared(preparation)
                )
            }
            mostRecent = preparation
            return preparation.request
        }

        public func latestPreparation() -> InferencePreparation? {
            mostRecent
        }
    }
}
