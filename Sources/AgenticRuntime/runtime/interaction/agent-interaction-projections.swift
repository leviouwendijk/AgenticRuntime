public extension AgentSuspension {
    func interactionRequest(
        sessionID: String
    ) -> AgentInteraction.Request {
        .init(
            sessionID: sessionID,
            suspension: self
        )
    }
}

public extension AgentRunResult {
    var interactionRequest: AgentInteraction.Request? {
        suspension?.interactionRequest(
            sessionID: sessionID
        )
    }
}

public extension AgentRunStateSnapshot {
    var interactionRequest: AgentInteraction.Request? {
        suspension?.interactionRequest(
            sessionID: sessionID
        )
    }
}
