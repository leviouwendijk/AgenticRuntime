import Agentic

public extension AgentRunner {
    struct Configuration: Sendable, Codable, Hashable {
        public var runLimits: AgentRunLimits
        public var contextMode: Context.Mode
        public var contextPolicy: Context.Policy
        public var appendToolResultsAsMessages: Bool
        public var autonomyMode: AutonomyMode
        public var executionLimits: ExecutionLimits
        public var recovery: Recovery.Policy?
        public var historyPersistenceMode: HistoryPersistenceMode
        public var compactionStrategy: CompactionStrategy?
        public var responseDelivery: AgentModelResponseDelivery
        public var streamCheckpointPolicy: AgentStreamCheckpointPolicy

        public init(
            runLimits: AgentRunLimits = .default,
            contextMode: Context.Mode = .accumulating,
            contextPolicy: Context.Policy = .init(),
            appendToolResultsAsMessages: Bool = true,
            autonomyMode: AutonomyMode = .auto_observe,
            executionLimits: ExecutionLimits = .unlimited,
            recovery: Recovery.Policy? = nil,
            historyPersistenceMode: HistoryPersistenceMode = .disabled,
            compactionStrategy: CompactionStrategy? = nil,
            responseDelivery: AgentModelResponseDelivery = .buffered,
            streamCheckpointPolicy: AgentStreamCheckpointPolicy = .default
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
        }

        private enum CodingKeys: String, CodingKey {
            case runLimits, contextMode, contextPolicy, appendToolResultsAsMessages
            case autonomyMode, executionLimits, recovery, historyPersistenceMode
            case compactionStrategy, responseDelivery, streamCheckpointPolicy
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                runLimits: try container.decode(AgentRunLimits.self, forKey: .runLimits),
                contextMode: try container.decodeIfPresent(Context.Mode.self, forKey: .contextMode) ?? .accumulating,
                contextPolicy: try container.decodeIfPresent(Context.Policy.self, forKey: .contextPolicy) ?? .init(),
                appendToolResultsAsMessages: try container.decode(Bool.self, forKey: .appendToolResultsAsMessages),
                autonomyMode: try container.decode(AutonomyMode.self, forKey: .autonomyMode),
                executionLimits: try container.decode(ExecutionLimits.self, forKey: .executionLimits),
                recovery: try container.decodeIfPresent(Recovery.Policy.self, forKey: .recovery),
                historyPersistenceMode: try container.decode(HistoryPersistenceMode.self, forKey: .historyPersistenceMode),
                compactionStrategy: try container.decodeIfPresent(CompactionStrategy.self, forKey: .compactionStrategy),
                responseDelivery: try container.decode(AgentModelResponseDelivery.self, forKey: .responseDelivery),
                streamCheckpointPolicy: try container.decode(AgentStreamCheckpointPolicy.self, forKey: .streamCheckpointPolicy)
            )
        }

        public static let `default` = Self()
    }
}

public extension AgentRunner.Configuration {
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

