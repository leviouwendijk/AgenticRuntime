import Agentic

enum RuntimeToolCallBoundary:
    Error,
    Sendable
{
    case capabilities_changed
}

struct RuntimeToolCallResolver:
    ToolCallResolver,
    Sendable
{
    let resolver: GovernedAgentToolCallResolver
    let capabilityState: AgentCapabilityState
    /// Exact Tool identities presented in this model invocation, not a
    /// dynamically recomputed visibility set.
    let advertisedTools: Set<ToolIdentifier>

    func resolve(
        _ call: ToolCall
    ) async throws -> ToolCall.Response {
        let before = await capabilityState.snapshot()
        guard advertisedTools.contains(call.tool),
              before.available.tools.contains(call.tool)
        else {
            throw AgentToolCallResolutionError.toolNotVisible(call.tool)
        }
        let result = try await resolver.resolve(
            call
        )
        let after = await capabilityState.snapshot()

        guard before == after else {
            throw RuntimeToolCallBoundary
                .capabilities_changed
        }

        return result
    }
}
