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

    func resolve(
        _ call: ToolCall
    ) async throws -> ToolResult {
        let before = await capabilityState.snapshot()
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
