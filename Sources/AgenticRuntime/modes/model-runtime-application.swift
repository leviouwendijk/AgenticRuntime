import Agentic

public struct ModeRuntimeApplication: Sendable {
    public var selection: ModeSelection
    public var configuration: AgentRunner.Configuration
    public var modelSelection: AgentModelSelection
    public var toolRegistry: ToolRegistry
    public var skillRegistry: SkillRegistry
    public var loadedSkills: [AgentSkill]
    public var capabilityState: AgentCapabilityState
    public var missingSkillIdentifiers: [AgentSkillIdentifier]
    public var metadata: [String: String]

    public init(
        selection: ModeSelection,
        configuration: AgentRunner.Configuration,
        modelSelection: AgentModelSelection,
        toolRegistry: ToolRegistry,
        skillRegistry: SkillRegistry,
        loadedSkills: [AgentSkill],
        capabilityState: AgentCapabilityState,
        missingSkillIdentifiers: [AgentSkillIdentifier],
        metadata: [String: String] = [:]
    ) {
        self.selection = selection
        self.configuration = configuration
        self.modelSelection = modelSelection
        self.toolRegistry = toolRegistry
        self.skillRegistry = skillRegistry
        self.loadedSkills = loadedSkills
        self.capabilityState = capabilityState
        self.missingSkillIdentifiers = missingSkillIdentifiers
        self.metadata = metadata
    }

    /// Build a mode application borrowing an already-established, authoritative
    /// ``AgentCapabilityState`` (for example produced by
    /// ``AgentRealization.makeCapabilityState()``).
    ///
    /// The mode supplies model routing, autonomy posture, loaded skills, and
    /// metadata. It must NOT silently manufacture a fresh visibility authority:
    /// that would discard an agent's authored visible capabilities. The caller
    /// is therefore responsible for passing the single live capability state
    /// that a realized agent has established.
    public init(
        selection: ModeSelection,
        configuration: AgentRunner.Configuration = .default,
        tools: ToolRegistry,
        capabilityState: AgentCapabilityState,
        skills: SkillRegistry = .init(),
        metadata additionalMetadata: [String: String] = [:]
    ) throws {
        let selectedSkills = try skills.selecting(
            selection.loadedSkillIdentifiers
        )
        var effectiveConfiguration = configuration
        effectiveConfiguration.autonomyMode = selection.mode.autonomyMode
        let metadata = selection.metadata.merging(
            additionalMetadata
        ) { _, new in
            new
        }

        self.init(
            selection: selection,
            configuration: effectiveConfiguration,
            modelSelection: selection.modelSelection,
            toolRegistry: tools,
            skillRegistry: selectedSkills.registry,
            loadedSkills: selectedSkills.loadedSkills,
            capabilityState: capabilityState,
            missingSkillIdentifiers: selectedSkills.missingIdentifiers,
            metadata: metadata
        )
    }

    public var modeID: ModeIdentifier {
        selection.modeID
    }

    /// Project the current, Agent-authorized visible Tools, not the Mode's
    /// historically declared exposed-tool selection.
    public func modelFacingToolDefinitions() async throws -> [ToolDescriptor] {
        let visible = await capabilityState.visible
        return try toolRegistry.modelFacingDefinitions(
            for: visible.tools
        )
    }
}
