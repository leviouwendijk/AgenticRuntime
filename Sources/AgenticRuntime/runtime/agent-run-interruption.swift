import Foundation

public enum Run {}

public extension Run {
    struct Interruption:
        Sendable,
        Codable,
        Hashable
    {
        public let mode: Mode
        public let reason: String?

        public init(
            mode: Mode,
            reason: String? = nil
        ) {
            self.mode = mode
            self.reason = reason
        }

        public enum Mode:
            String,
            Sendable,
            Codable,
            Hashable,
            CaseIterable
        {
            // Finish the current executor-defined stable unit/boundary, then stop before
            // starting more work.
            case graceful

            // Stop at the earliest safe boundary. Streaming model output may be cancelled
            // immediately; an already-running effectful tool is allowed to settle first.
            case urgent
        }
    }
}

public extension Run {
    actor Control {
        private var interruption: Interruption?

        public init() {}

        public func request(
            _ mode: Interruption.Mode,
            reason: String? = nil
        ) {
            if interruption?.mode == .urgent {
                return
            }

            interruption = .init(
                mode: mode,
                reason: reason
            )
        }

        public func current() -> Interruption? {
            interruption
        }

        public func clear() {
            interruption = nil
        }
    }
}

// MARK: - Deprecated compatibility aliases



