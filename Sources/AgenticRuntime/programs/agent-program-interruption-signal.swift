import Agentic

struct ProgramInterruptionSignal: Error, Sendable {
    let request: Run.Interruption
}
