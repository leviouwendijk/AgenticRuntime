import Agentic
import AgenticExecution

public struct ModeRuntimeApplication: Sendable {
    public var selection: ModeSelection
    public var configuration: AgentRunnerConfiguration
    public var routePolicy: AgentModelUsePolicy
    public var toolRegistry: ToolRegistry
    public var skillRegistry: SkillRegistry
    public var loadedSkills: [AgentSkill]
    public var missingSkillIdentifiers: [AgentSkillIdentifier]
    public var metadata: [String: String]

    public init(
        selection: ModeSelection,
        configuration: AgentRunnerConfiguration,
        routePolicy: AgentModelUsePolicy,
        toolRegistry: ToolRegistry,
        skillRegistry: SkillRegistry,
        loadedSkills: [AgentSkill],
        missingSkillIdentifiers: [AgentSkillIdentifier],
        metadata: [String: String] = [:]
    ) {
        self.selection = selection
        self.configuration = configuration
        self.routePolicy = routePolicy
        self.toolRegistry = toolRegistry
        self.skillRegistry = skillRegistry
        self.loadedSkills = loadedSkills
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
        let selectedTools = try tools.selecting(
            selection.exposedToolIdentifiers
        )
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
            routePolicy: selection.routePolicy,
            toolRegistry: selectedTools,
            skillRegistry: selectedSkills.registry,
            loadedSkills: selectedSkills.loadedSkills,
            missingSkillIdentifiers: selectedSkills.missingIdentifiers,
            metadata: metadata
        )
    }

    public var modeID: AgenticModeIdentifier {
        selection.modeID
    }

    public var toolDefinitions: [AgentToolDefinition] {
        toolRegistry.definitions
    }
}
