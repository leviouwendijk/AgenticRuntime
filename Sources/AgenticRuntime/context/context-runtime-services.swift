import Agentic
import AgenticContextWindow

public extension ContextWindow {
    /// Explicitly provided source authority for a Runner's allocated sessions.
    /// Installed capabilities do not grant source access on their own.
    struct Services: Sendable {
        public let resolver: any RecordResolving
        public let modelContextLimit: Int
        public let audit: (any InferenceAuditRecording)?
        /// The session's compactions, applied to every request.
        public let compactions: CompactionLedger?
        /// The provider's counts of the session's requests, anchoring the
        /// estimate of each next one.
        public let inputMeter: InputMeter?
        /// The session's previous request per model, naming each cache miss.
        public let cacheMeter: CacheMeter?

        public init(
            resolver: any RecordResolving,
            modelContextLimit: Int,
            audit: (any InferenceAuditRecording)? = nil,
            compactions: CompactionLedger? = nil,
            inputMeter: InputMeter? = nil,
            cacheMeter: CacheMeter? = nil
        ) {
            self.resolver = resolver
            self.modelContextLimit = modelContextLimit
            self.audit = audit
            self.compactions = compactions
            self.inputMeter = inputMeter
            self.cacheMeter = cacheMeter
        }
    }

    /// Dynamic mode can run with an empty working set and no source mount.
    /// Resolving an unmounted allocation must fail closed, not read arbitrarily.
    struct UnmountedResolver: RecordResolving {
        public init() {}

        public func resolve(_ pointer: Pointer) async throws -> Resolved {
            throw ContextEvidenceError.unavailableRecord(pointer.record)
        }
    }
}

public enum ContextExecutionError: Error, Sendable, Equatable {
    case requiresDynamicMode
    case incompatibleCompaction
    case checkpointModeChanged
    case checkpointPolicyChanged
}
