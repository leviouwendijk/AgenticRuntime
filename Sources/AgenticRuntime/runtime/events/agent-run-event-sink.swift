import Agentic

public protocol AgentRunEventSink: Sendable {
    func recordMessage(
        _ message: Message
    ) async throws

    func recordToolCall(
        _ toolCall: ToolCall
    ) async throws

    func recordToolResult(
        _ result: ToolResult
    ) async throws

    func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws

    func recordSessionBranch(
        _ event: SessionBranchEvent
    ) async throws
}

public extension AgentRunEventSink {
    func recordMessage(
        _ message: Message
    ) async throws {
    }

    func recordToolCall(
        _ toolCall: ToolCall
    ) async throws {
    }

    func recordToolResult(
        _ result: ToolResult
    ) async throws {
    }

    func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws {
    }

    func recordSessionBranch(
        _ event: SessionBranchEvent
    ) async throws {
    }
}
