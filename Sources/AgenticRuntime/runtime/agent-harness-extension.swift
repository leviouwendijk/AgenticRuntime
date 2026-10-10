import Agentic

public protocol AgentHarnessExtension: Sendable {
    func prepare(
        request: AgentRequest,
        state: AgentRunner.State
    ) async throws -> AgentRequest

    func didReceive(
        response: AgentResponse,
        state: AgentRunner.State
    ) async throws
}

public extension AgentHarnessExtension {
    func prepare(
        request: AgentRequest,
        state: AgentRunner.State
    ) async throws -> AgentRequest {
        request
    }

    func didReceive(
        response: AgentResponse,
        state: AgentRunner.State
    ) async throws {
    }
}
