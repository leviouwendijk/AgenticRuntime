import AgenticExecution
import AgenticIO
import AgenticStandard

public struct CoreToolSet: AgentToolProvider {
    public let contextComposer: ContextComposer
    public let includeInteractionTools: Bool
    // public let fileMutationRecorder: AgentFileMutationRecorder?

    public init(
        contextComposer: ContextComposer = .init(),
        includeInteractionTools: Bool = false,
        // fileMutationRecorder: AgentFileMutationRecorder? = nil
    ) {
        self.contextComposer = contextComposer
        self.includeInteractionTools = includeInteractionTools
        // self.fileMutationRecorder = fileMutationRecorder
    }

    public func registerTools(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            CoreFileToolSet()
            CoreWorkspaceToolSet()

            // CoreFileToolSet(
            //     fileMutationRecorder: fileMutationRecorder
            // )

            CoreContextToolSet(
                composer: contextComposer
            )

            if includeInteractionTools {
                Standard.Tools.ClarifyWithUser()
            }
        }
    }
}
