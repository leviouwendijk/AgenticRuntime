import Agentic

extension AgentLoop {
    @available(
        *,
        deprecated,
        renamed: "runControl"
    )
    var interruptionController: Run.Control {
        runControl
    }
}
