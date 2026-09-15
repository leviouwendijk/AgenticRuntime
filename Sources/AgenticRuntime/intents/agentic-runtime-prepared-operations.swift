import AgenticExecution
import AgenticIO

public enum AgenticRuntimePreparedOperations {
    public static func registry(
        fileMutationRecorder: AgentFileMutationRecorder? = nil,
        workspaceAccessActivator:
            (any AgentWorkspaceAccessActivating)? = nil
    ) throws -> PreparedOperationRegistry {
        var registry = PreparedOperationRegistry()

        try AgenticIOPreparedOperationSet(
            fileMutationRecorder: fileMutationRecorder
        ).register(
            into: &registry
        )

        if let workspaceAccessActivator {
            try registry.register(
                PreparedPathGrantExecutor(
                    activator: workspaceAccessActivator
                )
            )
        }

        return registry
    }
}
