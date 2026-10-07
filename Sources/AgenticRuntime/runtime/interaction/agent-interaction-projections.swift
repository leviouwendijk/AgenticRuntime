public extension Run.Suspension {
    func interactionRequest(
        sessionID: String
    ) -> Run.Interaction.Request {
        .init(
            sessionID: sessionID,
            suspension: self
        )
    }
}

public extension AgentRunResult {
    var interactionRequest: Run.Interaction.Request? {
        suspension?.interactionRequest(
            sessionID: sessionID
        )
    }
}

public extension AgentRunStateSnapshot {
    var interactionRequest: Run.Interaction.Request? {
        suspension?.interactionRequest(
            sessionID: sessionID
        )
    }
}
