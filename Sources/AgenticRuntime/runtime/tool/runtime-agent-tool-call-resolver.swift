import Agentic

enum RuntimeToolCallBoundary:
    Error,
    Sendable
{
    case exposure_changed
}

struct RuntimeToolCallResolver:
    ToolCallResolver,
    Sendable
{
    let resolver: GovernedAgentToolCallResolver
    let registry: ToolRegistry
    let exposure: AgentToolExposure

    func resolve(
        _ call: ToolCall
    ) async throws -> ToolResult {
        let before = Set(
            try await exposure.identifiers(
                in: registry
            )
        )

        let result = try await resolver.resolve(
            call
        )

        let after = Set(
            try await exposure.identifiers(
                in: registry
            )
        )

        guard before == after else {
            throw RuntimeToolCallBoundary
                .exposure_changed
        }

        return result
    }
}
