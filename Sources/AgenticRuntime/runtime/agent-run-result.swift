import Agentic

public struct AgentRunResult: Sendable, Codable, Hashable {
    public let sessionID: String
    public let response: AgentResponse?
    public let suspension: AgentSuspension?
    public let pendingApproval: PendingApproval?
    public let state: AgentLoopState
    public let events: [AgentRunEvent]
    public let costRecord: AgentCostRecord?

    public init(
        sessionID: String,
        response: AgentResponse?,
        suspension: AgentSuspension? = nil,
        pendingApproval: PendingApproval? = nil,
        state: AgentLoopState,
        events: [AgentRunEvent] = [],
        costRecord: AgentCostRecord? = nil
    ) {
        self.sessionID = sessionID
        self.response = response
        self.suspension = suspension
        self.pendingApproval = pendingApproval ?? suspension?.pendingApproval
        self.state = state
        self.events = events
        self.costRecord = costRecord
    }

    public static func completed(
        sessionID: String,
        response: AgentResponse,
        state: AgentLoopState,
        events: [AgentRunEvent] = [],
        costRecord: AgentCostRecord? = nil
    ) -> Self {
        .init(
            sessionID: sessionID,
            response: response,
            suspension: nil,
            pendingApproval: nil,
            state: state,
            events: events,
            costRecord: costRecord
        )
    }

    public static func suspended(
        sessionID: String,
        response: AgentResponse,
        suspension: AgentSuspension,
        state: AgentLoopState,
        events: [AgentRunEvent] = [],
        costRecord: AgentCostRecord? = nil
    ) -> Self {
        .init(
            sessionID: sessionID,
            response: response,
            suspension: suspension,
            pendingApproval: suspension.pendingApproval,
            state: state,
            events: events,
            costRecord: costRecord
        )
    }

    public static func awaitingApproval(
        sessionID: String,
        response: AgentResponse,
        pendingApproval: PendingApproval,
        state: AgentLoopState,
        events: [AgentRunEvent] = [],
        costRecord: AgentCostRecord? = nil
    ) -> Self {
        .suspended(
            sessionID: sessionID,
            response: response,
            suspension: .approval(
                pendingApproval
            ),
            state: state,
            events: events,
            costRecord: costRecord
        )
    }

    public static func awaitingUserInput(
        sessionID: String,
        response: AgentResponse,
        pendingUserInput: PendingUserInput,
        state: AgentLoopState,
        events: [AgentRunEvent] = [],
        costRecord: AgentCostRecord? = nil
    ) -> Self {
        .suspended(
            sessionID: sessionID,
            response: response,
            suspension: .user_input(
                pendingUserInput
            ),
            state: state,
            events: events,
            costRecord: costRecord
        )
    }

    public var pendingUserInput: PendingUserInput? {
        suspension?.pendingUserInput
    }

    public var isCompleted: Bool {
        response != nil && suspension == nil && pendingApproval == nil
    }

    public var isSuspended: Bool {
        suspension != nil || pendingApproval != nil
    }

    public var isAwaitingApproval: Bool {
        pendingApproval != nil || suspension?.pendingApproval != nil
    }

    public var isAwaitingUserInput: Bool {
        pendingUserInput != nil
    }
}
