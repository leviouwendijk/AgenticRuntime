import Agentic

public extension Context {
    /// Explicitly provided source authority for a Runner's allocated sessions.
    /// Installed capabilities do not grant source access on their own.
    struct Services: Sendable {
        public let resolver: any RecordResolving
        public let modelContextLimit: Int
        public let audit: (any InferenceAuditRecording)?

        public init(
            resolver: any RecordResolving,
            modelContextLimit: Int,
            audit: (any InferenceAuditRecording)? = nil
        ) {
            self.resolver = resolver
            self.modelContextLimit = modelContextLimit
            self.audit = audit
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
