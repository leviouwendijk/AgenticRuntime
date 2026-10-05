import Agentic

public extension AgenticRuntime {
    func makeAgentRunner(
        identifiedBy identifier: AgentIdentifier,
        model: AgentRuntimeServices.Model,
        configuration: AgentRunnerConfiguration = .default,
        tooling: AgentRuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: AgentRuntimeServices.Recording = .init()
    ) throws -> AgentRunner {
        let realization = try realizeAgent(
            identifiedBy: identifier
        )

        return AgentRunner(
            model: model.selecting(
                realization.modelSelection
            ),
            configuration: configuration,
            tooling: tooling.using(
                registry: tools
            ),
            capabilityState: realization.makeCapabilityState(),
            extensions: extensions,
            recording: recording
        )
    }

    func runAgent(
        identifiedBy identifier: AgentIdentifier,
        request: AgentRequest,
        model: AgentRuntimeServices.Model,
        configuration: AgentRunnerConfiguration = .default,
        tooling: AgentRuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: AgentRuntimeServices.Recording = .init(),
        sessionID: String
    ) async throws -> AgentRunResult {
        let runner = try makeAgentRunner(
            identifiedBy: identifier,
            model: model,
            configuration: configuration,
            tooling: tooling,
            extensions: extensions,
            recording: recording
        )

        return try await runner.run(
            request,
            sessionID: sessionID
        )
    }
}
