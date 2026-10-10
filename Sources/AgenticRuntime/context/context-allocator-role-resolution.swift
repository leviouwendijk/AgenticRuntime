import Agentic
import AgenticContext

/// Bind executable collaborators against the installed Runtime capabilities.
/// Context stores the resolved Core values, never Runtime's installation registry.
public extension Context.Allocator.Agent {
    init(
        resolving identifier: AgentIdentifier,
        in installed: InstalledCapabilities,
        modelPreferences: AgentModelPreferences = .init()
    ) throws {
        guard let binding = installed.agentBinding(identifier) else {
            throw ContextAllocatorError.unavailableAgent(identifier)
        }
        self.init(binding: binding, modelPreferences: modelPreferences)
    }
}

public extension Context.Allocator.Program {
    init(
        resolving identifier: ProgramIdentifier,
        in installed: InstalledCapabilities
    ) throws {
        guard let binding = installed.program(identifier) else {
            throw ContextAllocatorError.unavailableProgram(identifier)
        }
        self.init(binding: binding.program)
    }
}
