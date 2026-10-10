import Agentic

extension AgentRunner {
    @available(
        *,
        deprecated,
        renamed: "runControl"
    )
    public var interruptionController: Run.Control {
        runControl
    }
}
