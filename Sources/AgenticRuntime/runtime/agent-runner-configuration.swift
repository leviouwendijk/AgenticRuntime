import Agentic
import AgenticExecution

public struct AgentRunnerConfiguration: Sendable, Codable, Hashable {
    public var maximumIterations: Int
    public var appendToolResultsAsMessages: Bool
    public var autonomyMode: AutonomyMode
    public var executionLimits: ExecutionLimits
    public var historyPersistenceMode: HistoryPersistenceMode
    public var compactionStrategy: CompactionStrategy?
    public var responseDelivery: AgentModelResponseDelivery
    public var streamCheckpointPolicy: AgentStreamCheckpointPolicy

    public init(
        maximumIterations: Int = 12,
        appendToolResultsAsMessages: Bool = true,
        autonomyMode: AutonomyMode = .review_privileged,
        executionLimits: ExecutionLimits = .unlimited,
        historyPersistenceMode: HistoryPersistenceMode = .disabled,
        compactionStrategy: CompactionStrategy? = nil,
        responseDelivery: AgentModelResponseDelivery = .buffered,
        streamCheckpointPolicy: AgentStreamCheckpointPolicy = .default
    ) {
        self.maximumIterations = max(1, maximumIterations)
        self.appendToolResultsAsMessages = appendToolResultsAsMessages
        self.autonomyMode = autonomyMode
        self.executionLimits = executionLimits
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
