import Agentic

public struct AgentRunnerConfiguration: Sendable, Codable, Hashable {
    public var runLimits: AgentRunLimits
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
        self.appendToolResultsAsMessages = appendToolResultsAsMessages
        self.autonomyMode = autonomyMode
        self.executionLimits = executionLimits
        self.recovery = recovery
        self.historyPersistenceMode = historyPersistenceMode
        self.compactionStrategy = compactionStrategy
        self.responseDelivery = responseDelivery
        self.streamCheckpointPolicy = streamCheckpointPolicy
    }

    public static let `default` = Self()
}

public extension AgentRunnerConfiguration {
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
