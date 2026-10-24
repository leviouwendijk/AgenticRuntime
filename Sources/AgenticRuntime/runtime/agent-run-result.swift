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
        public let invocations: [AgentExecutionInvocation]
        public let toolUses: [AgentToolUseRecord]
        public let costRecord: AgentCostRecord?


        private enum CodingKeys: String, CodingKey {
            case sessionID, phase, response, suspension, pendingApproval, failure
            case state, events, toolUses, costRecord, invocations
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let sessionID = try container.decode(String.self, forKey: .sessionID)
            let phase = try container.decode(Phase.self, forKey: .phase)
            let response = try container.decodeIfPresent(AgentResponse.self, forKey: .response)
            let suspension = try container.decodeIfPresent(Run.Suspension.self, forKey: .suspension)
            let pendingApproval = try container.decodeIfPresent(PendingApproval.self, forKey: .pendingApproval)
            let failure = try container.decodeIfPresent(AgentRunFailure.self, forKey: .failure)
            let state = try container.decode(State.self, forKey: .state)
            let events = try container.decodeIfPresent([Run.Event.State].self, forKey: .events) ?? []
            let toolUses = try container.decodeIfPresent([AgentToolUseRecord].self, forKey: .toolUses) ?? []
            let costRecord = try container.decodeIfPresent(AgentCostRecord.self, forKey: .costRecord)
            let invocations = try container.decodeIfPresent([AgentExecutionInvocation].self, forKey: .invocations) ?? []
            self.init(
                sessionID: sessionID, phase: phase, response: response,
                suspension: suspension, pendingApproval: pendingApproval,
                failure: failure, state: state, events: events,
                toolUses: toolUses, costRecord: costRecord, invocations: invocations
            )
        }

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
            costRecord: AgentCostRecord? = nil,
            invocations: [AgentExecutionInvocation] = []
        ) {
            self.sessionID = sessionID
            self.phase = phase
            self.response = response
            self.suspension = suspension
            self.pendingApproval = pendingApproval ?? suspension?.pendingApproval
            self.failure = failure
            self.state = state
            self.events = events
            self.invocations = invocations
            self.toolUses = toolUses
            self.costRecord = costRecord
        }

        public static func completed(
            sessionID: String,
            response: AgentResponse,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil,
            invocations: [AgentExecutionInvocation] = []
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
                costRecord: costRecord,
                invocations: invocations
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
            costRecord: AgentCostRecord? = nil,
            invocations: [AgentExecutionInvocation] = []
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
                costRecord: costRecord,
                invocations: invocations
            )
        }

        public static func awaitingApproval(
            sessionID: String,
            response: AgentResponse,
            pendingApproval: PendingApproval,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil,
            invocations: [AgentExecutionInvocation] = []
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
                costRecord: costRecord,
                invocations: invocations
            )
        }

        public static func awaitingUserInput(
            sessionID: String,
            response: AgentResponse,
            pendingUserInput: UserInputRequest,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil,
            invocations: [AgentExecutionInvocation] = []
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
                costRecord: costRecord,
                invocations: invocations
            )
        }

        public static func interrupted(
            sessionID: String,
            response: AgentResponse? = nil,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil,
            invocations: [AgentExecutionInvocation] = []
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
                costRecord: costRecord,
                invocations: invocations
            )
        }

        public static func failed(
            sessionID: String,
            failure: AgentRunFailure,
            response: AgentResponse? = nil,
            state: State,
            events: [Run.Event.State] = [],
            toolUses: [AgentToolUseRecord] = [],
            costRecord: AgentCostRecord? = nil,
            invocations: [AgentExecutionInvocation] = []
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
                costRecord: costRecord,
                invocations: invocations
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

