import Agentic

public protocol AgentHarnessExtension: Sendable {
    func prepare(
        request: AgentRequest,
        state: AgentLoopState
    ) async throws -> AgentRequest

    func didReceive(
        response: AgentResponse,
        state: AgentLoopState
    ) async throws
}

public extension AgentHarnessExtension {
    func prepare(
        request: AgentRequest,
        state: AgentLoopState
    ) async throws -> AgentRequest {
        request
    }

    func didReceive(
        response: AgentResponse,
        state: AgentLoopState
    ) async throws {
    }
}
