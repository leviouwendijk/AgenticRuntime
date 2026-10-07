import Foundation

public enum AgentRunInterruptionMode:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    /// Finish the current agent iteration, including any already-started tool work,
    /// then stop before the next model turn.
    case after_iteration

    /// Stop at the earliest safe boundary. Streaming model output may be cancelled
    /// immediately; an already-running effectful tool is allowed to settle first.
    case urgent
}

public struct AgentRunInterruptionRequest:
    Sendable,
    Codable,
    Hashable
{
    public let mode: AgentRunInterruptionMode
    public let reason: String?

    public init(
        mode: AgentRunInterruptionMode,
        reason: String? = nil
    ) {
        self.mode = mode
        self.reason = reason
    }
}

public actor AgentRunInterruptionController {
    private var request: AgentRunInterruptionRequest?

    public init() {}

    public func request(
        _ mode: AgentRunInterruptionMode,
        reason: String? = nil
    ) {
        if request?.mode == .urgent {
            return
        }

        request = .init(
            mode: mode,
            reason: reason
        )
    }

    public func current() -> AgentRunInterruptionRequest? {
        request
    }

    public func clear() {
        request = nil
    }
}
