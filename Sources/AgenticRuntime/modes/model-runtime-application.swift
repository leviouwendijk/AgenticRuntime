import Agentic

public struct ModeRuntimeApplication: Sendable {
    public var selection: ModeSelection
    public var configuration: AgentRunner.Configuration
    public var modelSelection: AgentModelSelection
    public var toolRegistry: ToolRegistry
    /// Native, catalog-backed selection in the order requested by the Mode.
    public var selectedInstructions: Instructions
    public var missingInstructionIdentifiers: [InstructionIdentifier]

    public var instructions: Instructions { selectedInstructions }

    public var capabilityState: AgentCapabilityState
    public var metadata: [String: String]

    public init(
        selection: ModeSelection,
        configuration: AgentRunner.Configuration,
        modelSelection: AgentModelSelection,
        toolRegistry: ToolRegistry,
        capabilityState: AgentCapabilityState,
        metadata: [String: String] = [:],
        selectedInstructions: Instructions = Instructions([]),
        missingInstructionIdentifiers: [InstructionIdentifier] = []
    ) {
        self.selection = selection
        self.configuration = configuration
        self.modelSelection = modelSelection
        self.toolRegistry = toolRegistry
        self.selectedInstructions = selectedInstructions
        self.missingInstructionIdentifiers = missingInstructionIdentifiers
        self.capabilityState = capabilityState
        self.metadata = metadata
    }

    /// Build a mode application borrowing an already-established, authoritative
    /// ``AgentCapabilityState`` (for example produced by
    /// ``AgentRealization.makeCapabilityState()``).
    ///
    /// The mode supplies model routing, autonomy posture, selected instructions, and
    /// metadata. It must NOT silently manufacture a fresh visibility authority:
    /// that would discard an agent's authored visible capabilities. The caller
    /// is therefore responsible for passing the single live capability state
    /// that a realized agent has established.
    public init(
        selection: ModeSelection,
        configuration: AgentRunner.Configuration = .default,
        tools: ToolRegistry,
        capabilityState: AgentCapabilityState,
        instructionCatalog: Catalog = .none,
        metadata additionalMetadata: [String: String] = [:]
    ) throws {
        let selectedInstructions = try instructionCatalog.selectingInstructions(
            selection.loadedInstructionIdentifiers
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
            capabilityState: capabilityState,
            metadata: metadata,
            selectedInstructions: selectedInstructions.instructions,
            missingInstructionIdentifiers: selectedInstructions.missingIdentifiers
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
