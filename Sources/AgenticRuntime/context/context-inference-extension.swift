import Agentic
import AgenticContext

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
        /// Optional governed source of already-validated allocations.
        /// Callers may invoke a ContextPreparationProgram upstream.
        public let preparation: (any Context.PreparationSelecting)?
        private var mostRecent: InferencePreparation?

        public init(
            allocator: Allocator,
            workingSetID: String,
            resolver: any RecordResolving,
            modelContextLimit: Int,
            delivery: InferenceDelivery = .supplement,
            audit: (any InferenceAuditRecording)? = nil,
            preparation: (any Context.PreparationSelecting)? = nil
        ) {
            self.allocator = allocator
            self.workingSetID = workingSetID
            self.resolver = resolver
            self.modelContextLimit = modelContextLimit
            self.delivery = delivery
            self.audit = audit
            self.preparation = preparation
        }

        public func prepare(
            request: AgentRequest,
            state: AgentRunner.State
        ) async throws -> AgentRequest {
            mostRecent = nil
            if let preparation {
                let allocations = try await preparation.allocations(for: request)
                if !allocations.isEmpty {
                    try await allocator.apply(allocations.map { .allocate($0) },
                                              to: workingSetID)
                }
            }
            let frame = try await allocator.prepareFrame(
                for: workingSetID,
                using: resolver,
                modelContextLimit: modelContextLimit
            )
            let policy = await allocator.policy
            let maximum = max(
                0,
                min(
                    policy.maximumInputTokens,
                    modelContextLimit - policy.reservedOutputTokens
                )
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
