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

public extension AgentExecutor.Result {
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
