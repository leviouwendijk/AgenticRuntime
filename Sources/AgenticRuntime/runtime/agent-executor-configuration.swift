import Agentic

public extension AgentExecutor {
    struct Configuration: Sendable, Codable, Hashable {
        public var runLimits: AgentRunLimits
        public var contextMode: ContextWindow.Mode
        public var contextPolicy: ContextWindow.Policy
        public var appendToolResultsAsMessages: Bool
        public var autonomyMode: AutonomyMode
        public var executionLimits: ExecutionLimits
        public var recovery: Recovery.Policy?
        public var historyPersistenceMode: HistoryPersistenceMode
        public var compactionStrategy: CompactionStrategy?
        public var responseDelivery: AgentModelResponseDelivery
        public var streamCheckpointPolicy: AgentStreamCheckpointPolicy
        /// Lists, searches and inspects capabilities: the discovery tools
        /// the run installs are exposed whatever the Agent declares. Off for
        /// a fixed worker that must use only what it was shown.
        public var capabilityDiscovery: Bool

        public init(
            runLimits: AgentRunLimits = .default,
            contextMode: ContextWindow.Mode = .accumulating,
            contextPolicy: ContextWindow.Policy = .init(),
            appendToolResultsAsMessages: Bool = true,
            autonomyMode: AutonomyMode = .auto_observe,
            executionLimits: ExecutionLimits = .unlimited,
            recovery: Recovery.Policy? = nil,
            historyPersistenceMode: HistoryPersistenceMode = .disabled,
            compactionStrategy: CompactionStrategy? = nil,
            responseDelivery: AgentModelResponseDelivery = .buffered,
            streamCheckpointPolicy: AgentStreamCheckpointPolicy = .default,
            capabilityDiscovery: Bool = true
        ) {
            self.runLimits = runLimits
            self.contextMode = contextMode
            self.contextPolicy = contextPolicy
            self.appendToolResultsAsMessages = appendToolResultsAsMessages
            self.autonomyMode = autonomyMode
            self.executionLimits = executionLimits
            self.recovery = recovery
            self.historyPersistenceMode = historyPersistenceMode
            self.compactionStrategy = compactionStrategy
            self.responseDelivery = responseDelivery
            self.streamCheckpointPolicy = streamCheckpointPolicy
            self.capabilityDiscovery = capabilityDiscovery
        }

        private enum CodingKeys: String, CodingKey {
            case runLimits, contextMode, contextPolicy, appendToolResultsAsMessages
            case autonomyMode, executionLimits, recovery, historyPersistenceMode
            case compactionStrategy, responseDelivery, streamCheckpointPolicy
            case capabilityDiscovery
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                runLimits: try container.decode(AgentRunLimits.self, forKey: .runLimits),
                contextMode: try container.decodeIfPresent(ContextWindow.Mode.self, forKey: .contextMode) ?? .accumulating,
                contextPolicy: try container.decodeIfPresent(ContextWindow.Policy.self, forKey: .contextPolicy) ?? .init(),
                appendToolResultsAsMessages: try container.decode(Bool.self, forKey: .appendToolResultsAsMessages),
                autonomyMode: try container.decode(AutonomyMode.self, forKey: .autonomyMode),
                executionLimits: try container.decode(ExecutionLimits.self, forKey: .executionLimits),
                recovery: try container.decodeIfPresent(Recovery.Policy.self, forKey: .recovery),
                historyPersistenceMode: try container.decode(HistoryPersistenceMode.self, forKey: .historyPersistenceMode),
                compactionStrategy: try container.decodeIfPresent(CompactionStrategy.self, forKey: .compactionStrategy),
                responseDelivery: try container.decode(AgentModelResponseDelivery.self, forKey: .responseDelivery),
                streamCheckpointPolicy: try container.decode(AgentStreamCheckpointPolicy.self, forKey: .streamCheckpointPolicy),
                capabilityDiscovery: try container.decodeIfPresent(Bool.self, forKey: .capabilityDiscovery) ?? true
            )
        }

        public static let `default` = Self()
    }
}

public extension AgentExecutor.Configuration {
    var toolExecutionPolicy: ToolExecutionPolicy {
        .init(
            autonomyMode: autonomyMode,
            limits: executionLimits
        )
    }

    var persistsHistory: Bool {
        historyPersistenceMode != .disabled
    }

    var enablesCompaction: Bool {
        compactionStrategy != nil
    }
}

