import Agentic
import AgenticIO
import Workspace

public extension AgentRunner {
    struct Result: Sendable, Codable, Hashable {
        public let sessionID: String
        public let phase: Phase
        public let response: AgentResponse?
        public let suspension: Run.Suspension?
        public let pendingApproval: PendingApproval?
        public let failure: AgentRunFailure?
        public let state: State
        public let events: [Run.Event.State]
        public let toolUses: [AgentToolUseRecord]
        public let costRecord: AgentCostRecord?

        public init(
            sessionID: String,
            phase: Phase,
            response: AgentResponse?,
            suspension: Run.Suspension? = nil,
            pendingApproval: PendingApproval? = nil,
            failure: AgentRunFailure? = nil,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil
        ) {
            self.sessionID = sessionID
            self.phase = phase
            self.response = response
            self.suspension = suspension
            self.pendingApproval = pendingApproval ?? suspension?.pendingApproval
            self.failure = failure
            self.state = state
            self.events = events
            self.toolUses = toolUses
            self.costRecord = costRecord
        }

        public static func completed(
            sessionID: String,
            response: AgentResponse,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil
        ) -> Self {
            .init(
                sessionID: sessionID,
                phase: .completed,
                response: response,
                suspension: nil,
                pendingApproval: nil,
                state: state,
                events: events,
                toolUses: toolUses,
                costRecord: costRecord
            )
        }

        public static func suspended(
            sessionID: String,
            phase: Phase,
            response: AgentResponse?,
            suspension: Run.Suspension,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil
        ) -> Self {
            .init(
                sessionID: sessionID,
                phase: phase,
                response: response,
                suspension: suspension,
                pendingApproval: suspension.pendingApproval,
                state: state,
                events: events,
                toolUses: toolUses,
                costRecord: costRecord
            )
        }

        public static func awaitingApproval(
            sessionID: String,
            response: AgentResponse,
            pendingApproval: PendingApproval,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil
        ) -> Self {
            .suspended(
                sessionID: sessionID,
                phase: .awaiting_approval,
                response: response,
                suspension: .approval(
                    pendingApproval
                ),
                state: state,
                events: events,
                toolUses: toolUses,
                costRecord: costRecord
            )
        }

        public static func awaitingUserInput(
            sessionID: String,
            response: AgentResponse,
            pendingUserInput: UserInputRequest,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil
        ) -> Self {
            .suspended(
                sessionID: sessionID,
                phase: .suspended,
                response: response,
                suspension: .user_input(
                    pendingUserInput
                ),
                state: state,
                events: events,
                toolUses: toolUses,
                costRecord: costRecord
            )
        }

        public static func interrupted(
            sessionID: String,
            response: AgentResponse? = nil,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil
        ) -> Self {
            .init(
                sessionID: sessionID,
                phase: .interrupted,
                response: response,
                suspension: nil,
                pendingApproval: nil,
                failure: nil,
                state: state,
                events: events,
                toolUses: toolUses,
                costRecord: costRecord
            )
        }

        public static func failed(
            sessionID: String,
            failure: AgentRunFailure,
            response: AgentResponse? = nil,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil
        ) -> Self {
            .init(
                sessionID: sessionID,
                phase: .failed,
                response: response,
                suspension: nil,
                pendingApproval: nil,
                failure: failure,
                state: state,
                events: events,
                toolUses: toolUses,
                costRecord: costRecord
            )
        }

        public var pendingUserInput: UserInputRequest? {
            suspension?.pendingUserInput
        }

        public var pendingWorkspaceAccess: WorkspaceAccessRequest? {
            suspension?.pendingWorkspaceAccess
        }

        public var pendingRunLimit: AgentRunLimitExhaustion? {
            suspension?.pendingRunLimit
        }

        public var isCompleted: Bool {
            phase == .completed
        }

        public var isFailed: Bool {
            phase == .failed
        }

        public var isSuspended: Bool {
            phase == .suspended
                || phase == .awaiting_approval
        }

        public var isInterrupted: Bool {
            phase == .interrupted
        }

        public var isAwaitingApproval: Bool {
            pendingApproval != nil
                || suspension?.pendingApproval != nil
        }

        public var isAwaitingUserInput: Bool {
            pendingUserInput != nil
        }

        public var isAwaitingWorkspaceAccess: Bool {
            pendingWorkspaceAccess != nil
        }

        public var isAwaitingRunLimit: Bool {
            pendingRunLimit != nil
        }
    }
}

