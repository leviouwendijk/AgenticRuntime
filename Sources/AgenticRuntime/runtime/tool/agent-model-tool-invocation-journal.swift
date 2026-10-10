import Agentic

struct ModelSemanticInvocationResult: Sendable {
    let call: ToolCall
    let result: ToolCall.Response
}

actor AgentModelToolInvocationJournal {
    private var invocations: [ToolInvocation.Result] = []
    private var semanticInvocations: [ModelSemanticInvocationResult] = []

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

    func appendSemantic(
        call: ToolCall,
        result: ToolCall.Response
    ) {
        semanticInvocations.append(.init(call: call, result: result))
    }

    func semanticSnapshot() -> [ModelSemanticInvocationResult] {
        semanticInvocations
    }
}
