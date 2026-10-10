import Agentic

// Deprecated source-compatibility surfaces for downstream clients.
@available(*, deprecated, renamed: "ProgramExecutionBinding")
public typealias ProgramRegistration = ProgramExecutionBinding

@available(*, deprecated, renamed: "InferenceBinding")
public typealias InferenceRegistration = InferenceBinding

public extension AgenticApplication {
    @available(*, deprecated, renamed: "programBindings")
    var programRegistrations: [ProgramExecutionBinding] { programBindings }

    @available(*, deprecated, renamed: "inferenceBindings")
    var inferenceRegistrations: [InferenceBinding] { inferenceBindings }
}

public extension ProgramExecutionBinding {
    @available(*, deprecated, renamed: "program")
    var registeredProgram: ProgramBinding { program }
}

