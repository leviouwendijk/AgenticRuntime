import Agentic
import AgenticPrograms

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
    public var program: Program
    public var artifacts: (any AgentArtifactStore)?
    public var metadata: [String: String]

    public init(
        model: Model? = nil,
        program: Program = .init(),
        artifacts: (any AgentArtifactStore)? = nil,
        metadata: [String: String] = [:]
    ) {
        self.model = model
        self.program = program
        self.artifacts = artifacts
        self.metadata = metadata
    }
}
