import AgenticExecution

actor AgentModelToolInvocationJournal {
    private var invocations: [ToolInvocation.Result] = []

    func append(
        _ invocation: ToolInvocation.Result
    ) {
        invocations.append(
            invocation
        )
    }

    func snapshot() -> [ToolInvocation.Result] {
        invocations
    }
}
