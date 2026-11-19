import Agentic
import Foundation

public extension AgentExecutor {
    enum Phase: String, Sendable, Codable, Hashable, CaseIterable {
        case ready_for_model
        case receiving_model_response
        case processing_tool_calls
        case suspended
        case awaiting_approval
        case interrupted
        case failed
        case completed
    }

    struct Checkpoint: Sendable, Codable, Hashable, Identifiable {
        public let id: String
        /// The run's request settings: generation, response format,
        /// invocation options, metadata. The conversation lives in
        /// `state.messages` and capabilities are projected each turn, so
        /// neither is kept here; a checkpoint never holds the transcript twice.
        public let request: AgentRequest
        public var state: State
        public var runLimits: AgentRunLimits
        public var contextMode: ContextWindow.Mode
        public var contextPolicy: ContextWindow.Policy
        public var contextWorkingSet: ContextWindow.WorkingSet?
        public var contextTransitions: [ContextWindow.Transition]
        public var events: [Run.Event.State]
        /// Authoritative invocation spans, independently of display projections.
        public var invocations: [AgentExecutionInvocation]
        /// Last provider request span that causally produced tool calls.
        public var currentModelInvocationID: String?
        public var phase: Phase
        public var lastResponse: AgentResponse?
        public var partialResponse: AgentPartialResponse?
        public var toolBatch: AgentToolUseBatch?
        /// Persisted mapping for the last actual provider request. Nil on
        /// legacy checkpoints fails closed for model Tool execution.
        public var lastAdvertisedTools: [ToolIdentifier]?
        /// The original, validated function-to-target mapping for the provider
        /// request. Restored calls never bind against a newly derived projection.
        public var lastAdvertisedCapabilities: ModelCapabilityProjection?
        public var toolUses: [AgentToolUseRecord]
        public var suspension: Run.Suspension?
        public var pendingApproval: PendingApproval?
        public var failure: AgentRunFailure?
        public var costRecord: AgentCostRecord?
        public var capabilities: AgentCapabilityState.Snapshot
        /// The capabilities as the last `capability_changed` report left
        /// them; the next request reports what differs. Nil before the first.
        public var reportedCapabilities: AgentCapabilityState.Snapshot?
        /// The capabilities the run declares to the provider, in order:
        /// fixed at its first request, rebuilt only by a compaction. Nil
        /// before the first.
        public var declared: [CapabilityReference]?
        public let startedAt: Date
        public var updatedAt: Date

        private enum CodingKeys: String, CodingKey {
            case id
            case request
            case state
            case runLimits
            case contextMode
            case contextPolicy
            case contextWorkingSet
            case contextTransitions
            case events
            case invocations
            case currentModelInvocationID
            case phase
            case lastResponse
            case partialResponse
            case toolBatch
            case lastAdvertisedTools
            case lastAdvertisedCapabilities
            case toolUses
            case suspension
            case pendingApproval
            case failure
            case costRecord
            case capabilities
            case reportedCapabilities
            case declared
            case startedAt
            case updatedAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )

            id = try container.decode(
                String.self,
                forKey: .id
            )
            request = try container.decode(
                AgentRequest.self,
                forKey: .request
            ).settings
            state = try container.decode(
                State.self,
                forKey: .state
            )
            runLimits = try container.decode(
                AgentRunLimits.self,
                forKey: .runLimits
            )
            contextMode = try container.decodeIfPresent(
                ContextWindow.Mode.self,
                forKey: .contextMode
            ) ?? .accumulating
            contextPolicy = try container.decodeIfPresent(
                ContextWindow.Policy.self,
                forKey: .contextPolicy
            ) ?? .init()
            contextWorkingSet = try container.decodeIfPresent(
                ContextWindow.WorkingSet.self,
                forKey: .contextWorkingSet
            )
            contextTransitions = try container.decodeIfPresent(
                [ContextWindow.Transition].self,
                forKey: .contextTransitions
            ) ?? []
            events = try container.decodeIfPresent(
                [Run.Event.State].self,
                forKey: .events
            ) ?? []
            invocations = try container.decodeIfPresent(
                [AgentExecutionInvocation].self,
                forKey: .invocations
            ) ?? []
            currentModelInvocationID = try container.decodeIfPresent(
                String.self, forKey: .currentModelInvocationID
            )
            phase = try container.decode(
                Phase.self,
                forKey: .phase
            )
            lastResponse = try container.decodeIfPresent(
                AgentResponse.self,
                forKey: .lastResponse
            )
            partialResponse = try container.decodeIfPresent(
                AgentPartialResponse.self,
                forKey: .partialResponse
            )
            toolBatch = try container.decodeIfPresent(
                AgentToolUseBatch.self,
                forKey: .toolBatch
            )
            lastAdvertisedTools = try container.decodeIfPresent(
                [ToolIdentifier].self,
                forKey: .lastAdvertisedTools
            )
            lastAdvertisedCapabilities = try container.decodeIfPresent(
                ModelCapabilityProjection.self,
                forKey: .lastAdvertisedCapabilities
            )
            toolUses = try container.decodeIfPresent(
                [AgentToolUseRecord].self,
                forKey: .toolUses
            ) ?? []
            suspension = try container.decodeIfPresent(
                Run.Suspension.self,
                forKey: .suspension
            )
            let decodedPendingApproval = try container.decodeIfPresent(
                PendingApproval.self,
                forKey: .pendingApproval
            )
            pendingApproval = decodedPendingApproval
                ?? suspension?.pendingApproval
            failure = try container.decodeIfPresent(
                AgentRunFailure.self,
                forKey: .failure
            )
            costRecord = try container.decodeIfPresent(
                AgentCostRecord.self,
                forKey: .costRecord
            )
            capabilities = try container.decode(
                AgentCapabilityState.Snapshot.self,
                forKey: .capabilities
            )
            reportedCapabilities = try container.decodeIfPresent(
                AgentCapabilityState.Snapshot.self,
                forKey: .reportedCapabilities
            )
            declared = try container.decodeIfPresent(
                [CapabilityReference].self,
                forKey: .declared
            )
            let decodedUpdatedAt = try container.decode(
                Date.self,
                forKey: .updatedAt
            )
            startedAt = try container.decodeIfPresent(
                Date.self,
                forKey: .startedAt
            ) ?? decodedUpdatedAt
            updatedAt = decodedUpdatedAt
        }

        public init(
            id: String,
            request: AgentRequest,
            state: State,
            runLimits: AgentRunLimits,
            contextMode: ContextWindow.Mode = .accumulating,
            contextPolicy: ContextWindow.Policy = .init(),
            contextWorkingSet: ContextWindow.WorkingSet? = nil,
            contextTransitions: [ContextWindow.Transition] = [],
            events: [Run.Event.State] = [],
            invocations: [AgentExecutionInvocation] = [],
            currentModelInvocationID: String? = nil,
            phase: Phase = .ready_for_model,
            lastResponse: AgentResponse? = nil,
            partialResponse: AgentPartialResponse? = nil,
            toolBatch: AgentToolUseBatch? = nil,
            lastAdvertisedTools: [ToolIdentifier]? = nil,
            lastAdvertisedCapabilities: ModelCapabilityProjection? = nil,
            toolUses: [AgentToolUseRecord] = [],
            suspension: Run.Suspension? = nil,
            pendingApproval: PendingApproval? = nil,
            failure: AgentRunFailure? = nil,
            costRecord: AgentCostRecord? = nil,
            capabilities: AgentCapabilityState.Snapshot = .init(
                installed: .none,
                available: .none,
                visible: .none
            ),
            reportedCapabilities: AgentCapabilityState.Snapshot? = nil,
            declared: [CapabilityReference]? = nil,
            startedAt: Date = Date(),
            updatedAt: Date? = nil
        ) {
            self.id = id
            self.request = request.settings
            self.state = state
            self.runLimits = runLimits
            self.contextMode = contextMode
            self.contextPolicy = contextPolicy
            self.contextWorkingSet = contextWorkingSet
            self.contextTransitions = contextTransitions
            self.events = events
            self.invocations = invocations
            self.currentModelInvocationID = currentModelInvocationID
            self.phase = phase
            self.lastResponse = lastResponse
            self.partialResponse = partialResponse
            self.toolBatch = toolBatch
            self.lastAdvertisedTools = lastAdvertisedTools
            self.lastAdvertisedCapabilities = lastAdvertisedCapabilities
            self.toolUses = toolUses
            self.suspension = suspension
            self.pendingApproval = pendingApproval ?? suspension?.pendingApproval
            self.failure = failure
            self.costRecord = costRecord
            self.capabilities = capabilities
            self.reportedCapabilities = reportedCapabilities
            self.declared = declared
            self.startedAt = startedAt
            self.updatedAt = updatedAt ?? startedAt
        }
    }
}

public extension AgentExecutor.Checkpoint {
    var session: AgentSession {
        .init(
            id: id,
            messages: state.messages
        )
    }

    var resolvedSuspension: Run.Suspension? {
        if let suspension {
            return suspension
        }

        if let pendingApproval {
            return .approval(
                pendingApproval
            )
        }

        return nil
    }

    var pendingUserInput: UserInputRequest? {
        resolvedSuspension?.pendingUserInput
    }

    var pendingRunLimit: AgentRunLimitExhaustion? {
        resolvedSuspension?.pendingRunLimit
    }

    mutating func suspend(
        _ suspension: Run.Suspension
    ) {
        self.suspension = suspension
        self.pendingApproval = suspension.pendingApproval
        self.phase = .suspended
    }

    mutating func clearSuspension() {
        suspension = nil
        pendingApproval = nil

        if phase == .suspended || phase == .awaiting_approval {
            phase = .ready_for_model
        }
    }

    internal var resolvedToolUses: [AgentToolUseRecord] {
        var records = toolUses

        guard let toolBatch else {
            return records
        }

        for record in toolBatch.records {
            if let index = records.firstIndex(where: { existing in
                existing.id == record.id
            }) {
                records[index] = record
            } else {
                records.append(
                    record
                )
            }
        }

        return records
    }

    internal mutating func archiveToolUses(
        _ records: [AgentToolUseRecord]
    ) {
        for record in records {
            if let index = toolUses.firstIndex(where: { existing in
                existing.id == record.id
            }) {
                toolUses[index] = record
            } else {
                toolUses.append(
                    record
                )
            }
        }

        touch()
    }

    mutating func clearToolBatch() {
        toolBatch = nil
        touch()
    }

    mutating func touch(
        now: Date = Date()
    ) {
        updatedAt = now
    }
}

private extension AgentRequest {
    /// The request without its conversation and capability schemas.
    var settings: AgentRequest {
        var settings = self
        settings.messages = []
        settings.tools = []
        return settings
    }
}
