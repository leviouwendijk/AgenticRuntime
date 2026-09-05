public protocol AgentRunStateSink: Sendable {
    func publish(
        _ snapshot: AgentRunStateSnapshot
    ) async
}
