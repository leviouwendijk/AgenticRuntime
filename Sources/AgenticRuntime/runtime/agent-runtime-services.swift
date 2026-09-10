import Agentic
import AgenticExecution
import AgenticPrograms
import AgenticUsage
import AgenticWorkspace

/// Shared execution capabilities available to Runtime consumers.
///
/// Conversation, Program, and future child/task runners consume this common
/// substrate or one of its strong capability projections rather than defining
/// parallel Runtime service universes.
public struct AgentRuntimeServices: Sendable {
    /// Model invocation capability used by Runtime execution paths that perform
    /// semantic model work.
    ///
    /// Whenever a consumer receives a `Model`, both the invoker and its default
    /// selection posture are present.
    public struct Model: Sendable {
        public let invoker: any AgentModelInvoking
        public var selection: AgentModelSelection

        public init(
            invoker: any AgentModelInvoking,
            selection: AgentModelSelection = .executor
        ) {
            self.invoker = invoker
            self.selection = selection
        }

        public func selecting(
            _ selection: AgentModelSelection
        ) -> Self {
            .init(
                invoker: invoker,
                selection: selection
            )
        }
    }

    /// Governed tool execution capabilities shared by agent execution paths.
    ///
    /// Model-visible exposure is deliberately not stored here. Exposure is
    /// derived from run configuration and checkpoint state by the runner.
    public struct Tooling: Sendable {
        public var registry: ToolRegistry
        public var workspace: AgentWorkspace?
        public var approvalHandler: (any ToolApprovalHandler)?

        public init(
            registry: ToolRegistry = .init(),
            workspace: AgentWorkspace? = nil,
            approvalHandler: (any ToolApprovalHandler)? = nil
        ) {
            self.registry = registry
            self.workspace = workspace
            self.approvalHandler = approvalHandler
        }

        public func using(
            registry: ToolRegistry
        ) -> Self {
            .init(
                registry: registry,
                workspace: workspace,
                approvalHandler: approvalHandler
            )
        }

        public func using(
            workspace: AgentWorkspace?
        ) -> Self {
            .init(
                registry: registry,
                workspace: workspace,
                approvalHandler: approvalHandler
            )
        }
    }

    /// Run persistence, observation, and accounting capabilities.
    public struct Recording: Sendable {
        public var historyStore: (any AgentHistoryStore)?
        public var eventSinks: [any AgentRunEventSink]
        public var stateSinks: [any AgentRunStateSink]
        public var costTracker: AgentCostTracker?

        public init(
            historyStore: (any AgentHistoryStore)? = nil,
            eventSinks: [any AgentRunEventSink] = [],
            stateSinks: [any AgentRunStateSink] = [],
            costTracker: AgentCostTracker? = nil
        ) {
            self.historyStore = historyStore
            self.eventSinks = eventSinks
            self.stateSinks = stateSinks
            self.costTracker = costTracker
        }

        /// Resolves durable environment/session stores into this recording
        /// projection while retaining caller-provided observers and accounting.
        public func resolving(
            historyStore: (any AgentHistoryStore)?,
            eventSinks: [any AgentRunEventSink]
        ) -> Self {
            .init(
                historyStore: historyStore ?? self.historyStore,
                eventSinks: eventSinks + self.eventSinks,
                stateSinks: stateSinks,
                costTracker: costTracker
            )
        }
    }

    /// Program execution capabilities currently consumed by AgentProgramRunner.
    ///
    /// These remain explicitly grouped while their implementations are rebased
    /// onto the common model and governed execution substrate in later passes.
    public struct Program: Sendable {
        public var inference: (any AgentProgramInferenceExecuting)?
        public var tools: (any AgentProgramToolExecuting)?
        public var invoker: (any AgentProgramInvoking)?

        public init(
            inference: (any AgentProgramInferenceExecuting)? = nil,
            tools: (any AgentProgramToolExecuting)? = nil,
            invoker: (any AgentProgramInvoking)? = nil
        ) {
            self.inference = inference
            self.tools = tools
            self.invoker = invoker
        }
    }

    public var model: Model?
    public var tooling: Tooling
    public var recording: Recording
    public var program: Program
    public var artifacts: (any AgentArtifactStore)?
    public var metadata: [String: String]

    public init(
        model: Model? = nil,
        tooling: Tooling = .init(),
        recording: Recording = .init(),
        program: Program = .init(),
        artifacts: (any AgentArtifactStore)? = nil,
        metadata: [String: String] = [:]
    ) {
        self.model = model
        self.tooling = tooling
        self.recording = recording
        self.program = program
        self.artifacts = artifacts
        self.metadata = metadata
    }
}
