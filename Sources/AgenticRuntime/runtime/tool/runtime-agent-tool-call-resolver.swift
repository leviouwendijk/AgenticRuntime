import Agentic
import AgenticExecution

enum RuntimeAgentToolCallBoundary:
    Error,
    Sendable
{
    case exposure_changed
}

struct RuntimeAgentToolCallResolver:
    AgentToolCallResolver,
    Sendable
{
    let resolver: GovernedAgentToolCallResolver
    let registry: ToolRegistry
    let exposure: AgentToolExposure

    func resolve(
        _ call: AgentToolCall
    ) async throws -> AgentToolResult {
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
            throw RuntimeAgentToolCallBoundary
                .exposure_changed
        }

        return result
    }
}
