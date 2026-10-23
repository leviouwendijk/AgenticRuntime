// FROZEN: deferred queue (not conversational or ToolPlan execution).
#if AGENTIC_ENABLE_DEFERRED_INTENTS
import Agentic
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

#endif // AGENTIC_ENABLE_DEFERRED_INTENTS