import Agentic

public extension AgenticRuntime {
    func makeAgentExecutor(
        identifiedBy identifier: AgentIdentifier,
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        modelPreferences: AgentModelPreferences = .init()
    ) throws -> AgentExecutor {
        let realization = try realizeAgent(
            identifiedBy: identifier
        )
        return makeAgentExecutor(
            realization: realization,
            capabilityState: realization.makeCapabilityState(),
            model: model,
            configuration: configuration,
            tooling: tooling,
            extensions: extensions,
            recording: recording,
            modelPreferences: modelPreferences
        )
    }

    /// The same realized Agent and capability actor that admission checked must
    /// be installed in its runner. This is an internal Runtime seam, not a
    /// caller-controlled override of an Agent's authored permissions.
    internal func makeAgentExecutor(
        realization: AgentRealization,
        capabilityState: AgentCapabilityState,
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        delegation: AgentDelegation? = nil,
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        modelPreferences: AgentModelPreferences = .init()
    ) -> AgentExecutor {
        var selection = realization.modelSelection
        // A delegated runner receives the caller's resolved model posture.
        // Preserve that target unless this Agent or an explicit invocation
        // preference supplies a more specific one.
        selection.preferences = model.selection.preferences.overriding(
            with: selection.preferences
        ).overriding(
            with: modelPreferences
        )
        // Routing restrictions are inherited, never relaxed by a child.
        // Keep the child's purpose and capability requirements independent.
        selection.constraints = model.selection.constraints.tightened(
            by: selection.constraints
        )
        return AgentExecutor(
            model: model.selecting(selection),
            configuration: configuration,
            tooling: tooling.using(registry: tools),
            inventory: CapabilityInventory(
                installed: installed,
                state: capabilityState
            ),
            delegation: delegation,
            extensions: extensions,
            recording: recording
        )
    }

    /// Build an ``AgentExecutor`` for a realized Agent routed through a ``Mode``.
    ///
    /// The realized Agent establishes the single authoritative
    /// ``AgentCapabilityState`` (preserving authored visible capabilities). The
    /// mode contributes model routing, autonomy posture, instructions, and
    /// metadata but must NOT replace the Agent's capability authority.
    func makeModeAgentExecutor(
        identifiedBy identifier: AgentIdentifier,
        model: RuntimeServices.Model,
        selection: ModeSelection,
        configuration: AgentExecutor.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init()
    ) throws -> AgentExecutor {
        let realization = try realizeAgent(
            identifiedBy: identifier
        )
        let modeApplication = try ModeRuntimeApplication(
            selection: selection,
            configuration: configuration,
            tools: tools,
            capabilityState: realization.makeCapabilityState(),
            instructionCatalog: catalog
        )

        return AgentExecutor(
            model: model.selecting(
                realization.modelSelection
            ),
            configuration: modeApplication.configuration,
            tooling: tooling.using(
                registry: modeApplication.toolRegistry
            ),
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
        configuration: AgentExecutor.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        sessionID: String
    ) async throws -> AgentExecutor.Result {
        let executor = try makeModeAgentExecutor(
            identifiedBy: identifier,
            model: model,
            selection: selection,
            configuration: configuration,
            tooling: tooling,
            extensions: extensions,
            recording: recording
        )

        return try await executor.run(
            request,
            sessionID: sessionID
        )
    }

    func runAgent(
        identifiedBy identifier: AgentIdentifier,
        request: AgentRequest,
        model: RuntimeServices.Model,
        configuration: AgentExecutor.Configuration = .default,
        tooling: RuntimeServices.Tooling = .init(),
        extensions: [any AgentHarnessExtension] = [],
        recording: RuntimeServices.Recording = .init(),
        sessionID: String
    ) async throws -> AgentExecutor.Result {
        let executor = try makeAgentExecutor(
            identifiedBy: identifier,
            model: model,
            configuration: configuration,
            tooling: tooling,
            extensions: extensions,
            recording: recording
        )

        return try await executor.run(
            request,
            sessionID: sessionID
        )
    }
}
