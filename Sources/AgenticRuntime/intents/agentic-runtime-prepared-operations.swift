import AgenticExecution
import AgenticIO

public enum AgenticRuntimePreparedOperations {
    public static func registry(
        fileMutationRecorder: AgentFileMutationRecorder? = nil
    ) throws -> PreparedOperationRegistry {
        var registry = PreparedOperationRegistry()

        try AgenticIOPreparedOperationSet(
            fileMutationRecorder: fileMutationRecorder
        ).register(
            into: &registry
        )

        return registry
    }
}
