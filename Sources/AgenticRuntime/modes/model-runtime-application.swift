import Agentic

public struct ModeRuntimeApplication: Sendable {
    public var selection: ModeSelection
    public var configuration: AgentRunnerConfiguration
    public var modelSelection: AgentModelSelection
    public var toolRegistry: ToolRegistry
    public var skillRegistry: SkillRegistry
    public var loadedSkills: [AgentSkill]
    public var capabilityState: AgentCapabilityState
    public var missingSkillIdentifiers: [AgentSkillIdentifier]
    public var metadata: [String: String]

    public init(
        selection: ModeSelection,
        configuration: AgentRunnerConfiguration,
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

    public init(
        selection: ModeSelection,
        configuration: AgentRunnerConfiguration = .default,
        tools: ToolRegistry,
        skills: SkillRegistry = .init(),
        metadata additionalMetadata: [String: String] = [:]
    ) throws {
        _ = try tools.modelFacingDefinitions(
            for: selection.exposedToolIdentifiers
        )
        let selectedSkills = try skills.selecting(
            selection.loadedSkillIdentifiers
        )
        var effectiveConfiguration = configuration
        effectiveConfiguration.autonomyMode = selection.mode.autonomyMode
        let installed = AgentCapabilitySet(
            tools: tools.modelFacingDefinitions.map(
                \.identifier
            )
        )
        let capabilityState = AgentCapabilityState(
            installed: installed,
            available: installed,
            visible: .init(
                tools: selection.exposedToolIdentifiers
            )
        )
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

    public var toolDefinitions: [ToolDescriptor] {
        let selected = Set(
            selection.exposedToolIdentifiers
        )

        return toolRegistry.modelFacingDefinitions.filter { definition in
            selected.contains(
                definition.identifier
            )
        }
    }
}
