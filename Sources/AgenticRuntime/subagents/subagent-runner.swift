public struct SubagentRunner: Sendable {
    public let runner: AgentRunner
    public let summaryStrategy: SubagentSummaryStrategy

    public init(
        runner: AgentRunner,
        summaryStrategy: SubagentSummaryStrategy = .finalmessage
    ) {
        self.runner = runner
        self.summaryStrategy = summaryStrategy
    }
}
