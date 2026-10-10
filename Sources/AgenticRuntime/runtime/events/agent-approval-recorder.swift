public actor AgentApprovalRecorder: Run.EventSink {
    public let sessionID: String
    public let store: any AgentApprovalEventStore

    public init(
        sessionID: String,
        store: any AgentApprovalEventStore
    ) {
        self.sessionID = sessionID
        self.store = store
    }

    public func record(
        _ event: Run.Event
    ) async throws {
        switch event {
        case .state(let state):
            guard let approvalEvent = AgentApprovalEvent(
                sessionID: sessionID,
                runEvent: state
            ) else {
                return
            }

            try await store.append(
                approvalEvent
            )

        case .tool_observation:
            return
        }
    }
}
