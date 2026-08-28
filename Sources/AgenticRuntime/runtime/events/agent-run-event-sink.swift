import Agentic

public protocol AgentRunEventSink: Sendable {
    func recordMessage(
        _ message: AgentMessage
    ) async throws

    func recordToolCall(
        _ toolCall: AgentToolCall
    ) async throws

    func recordToolResult(
        _ result: AgentToolResult
    ) async throws

    func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws

    func recordSessionBranch(
        _ event: AgentSessionBranchEvent
    ) async throws
}

public extension AgentRunEventSink {
    func recordMessage(
        _ message: AgentMessage
    ) async throws {
    }

    func recordToolCall(
        _ toolCall: AgentToolCall
    ) async throws {
    }

    func recordToolResult(
        _ result: AgentToolResult
    ) async throws {
    }

    func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws {
    }

    func recordSessionBranch(
        _ event: AgentSessionBranchEvent
    ) async throws {
    }
}
