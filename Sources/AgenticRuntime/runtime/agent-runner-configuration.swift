import Agentic

public struct AgentRunnerConfiguration: Sendable, Codable, Hashable {
    public var maximumIterations: Int
    public var appendToolResultsAsMessages: Bool
    public var autonomyMode: AutonomyMode
    public var executionLimits: ExecutionLimits
    public var recovery: Recovery.Policy?
    public var historyPersistenceMode: HistoryPersistenceMode
    public var compactionStrategy: CompactionStrategy?
    /// Concrete capabilities available to this agent invocation.
    /// `nil` preserves the legacy/ad-hoc posture of making every installed
    /// capability available. Runtime still intersects explicit selections
    /// with the installed executable universe.
    public var availableCapabilities: AgentCapabilitySet?
    /// Transitional initial visibility preset. This no longer defines
    /// capability availability.
    public var toolExposure: AgentToolExposurePolicy
    public var responseDelivery: AgentModelResponseDelivery
    public var streamCheckpointPolicy: AgentStreamCheckpointPolicy

    public init(
        maximumIterations: Int = 12,
        appendToolResultsAsMessages: Bool = true,
        autonomyMode: AutonomyMode = .auto_observe,
        executionLimits: ExecutionLimits = .unlimited,
        recovery: Recovery.Policy? = nil,
        historyPersistenceMode: HistoryPersistenceMode = .disabled,
        compactionStrategy: CompactionStrategy? = nil,
        availableCapabilities: AgentCapabilitySet? = nil,
        toolExposure: AgentToolExposurePolicy = .all,
        responseDelivery: AgentModelResponseDelivery = .buffered,
        streamCheckpointPolicy: AgentStreamCheckpointPolicy = .default
    ) {
        self.maximumIterations = max(1, maximumIterations)
        self.appendToolResultsAsMessages = appendToolResultsAsMessages
        self.autonomyMode = autonomyMode
        self.executionLimits = executionLimits
        self.recovery = recovery
        self.historyPersistenceMode = historyPersistenceMode
        self.compactionStrategy = compactionStrategy
        self.availableCapabilities = availableCapabilities
        self.toolExposure = toolExposure
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
