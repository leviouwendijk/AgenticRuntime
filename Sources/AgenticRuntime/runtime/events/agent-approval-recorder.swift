public actor AgentApprovalRecorder: AgentRunEventSink {
    public let sessionID: String
    public let store: any AgentApprovalEventStore

    public init(
        sessionID: String,
        store: any AgentApprovalEventStore
    ) {
        self.sessionID = sessionID
        self.store = store
    }

    public func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws {
        guard let approvalEvent = AgentApprovalEvent(
            sessionID: sessionID,
            runEvent: event
        ) else {
            return
        }

        try await store.append(
            approvalEvent
        )
    }
}
