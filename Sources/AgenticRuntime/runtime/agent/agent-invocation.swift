import Agentic

public extension AgenticRuntime {
    func makeAgentRunner(
        identifiedBy identifier: AgentIdentifier,
        model: RuntimeServices.Model,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        modelPreferences: AgentModelPreferences = .init()
    ) throws -> AgentRunner {
        let realization = try realizeAgent(
            identifiedBy: identifier
        )

        let state = realization.makeCapabilityState()
        var modelSelection = realization.modelSelection
        modelSelection.preferences = modelSelection.preferences.overriding(
            with: modelPreferences
        )
        return AgentRunner(
            model: model.selecting(
                modelSelection
            ),
            configuration: configuration,
            tooling: tooling.using(
                registry: tools
            ),
            capabilityState: state,
            inventory: CapabilityInventory(
                installed: installed,
                state: state
            ),
            extensions: extensions,
            recording: recording
        )
    }

    /// Build an ``AgentRunner`` for a realized Agent routed through a ``Mode``.
    ///
    /// The realized Agent establishes the single authoritative
    /// ``AgentCapabilityState`` (preserving authored visible capabilities). The
    /// mode contributes model routing, autonomy posture, loaded skills, and
    /// metadata but must NOT replace the Agent's capability authority.
    func makeModeAgentRunner(
        identifiedBy identifier: AgentIdentifier,
        model: RuntimeServices.Model,
        selection: ModeSelection,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        skills: SkillRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init()
    ) throws -> AgentRunner {
        let realization = try realizeAgent(
            identifiedBy: identifier
        )
        let modeApplication = try ModeRuntimeApplication(
            selection: selection,
            configuration: configuration,
            tools: tools,
            capabilityState: realization.makeCapabilityState(),
            skills: skills
        )

        return AgentRunner(
            model: model.selecting(
                realization.modelSelection
            ),
            configuration: modeApplication.configuration,
            tooling: tooling.using(
                registry: modeApplication.toolRegistry
            ),
            capabilityState: modeApplication.capabilityState,
            inventory: CapabilityInventory(
                installed: installed,
                state: modeApplication.capabilityState
            ),
            extensions: extensions,
            recording: recording
        )
    }

    func runModeAgent(
        identifiedBy identifier: AgentIdentifier,
        request: AgentRequest,
        model: RuntimeServices.Model,
        selection: ModeSelection,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        skills: SkillRegistry = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        sessionID: String
    ) async throws -> AgentRunner.Result {
        let runner = try makeModeAgentRunner(
            identifiedBy: identifier,
            model: model,
            selection: selection,
            configuration: configuration,
            tooling: tooling,
            skills: skills,
            extensions: extensions,
            recording: recording
        )

        return try await runner.run(
            request,
            sessionID: sessionID
        )
    }

    func runAgent(
        identifiedBy identifier: AgentIdentifier,
        request: AgentRequest,
        model: RuntimeServices.Model,
        configuration: AgentRunner.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        sessionID: String
    ) async throws -> AgentRunner.Result {
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
