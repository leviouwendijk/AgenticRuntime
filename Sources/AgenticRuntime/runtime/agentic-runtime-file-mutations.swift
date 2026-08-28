import Agentic
import AgenticIO
import Foundation

public extension Agentic.RuntimeBootstrapAPI {
    func fileMutationStore(
        sessionID: String,
        environment: AgentRuntimeEnvironment
    ) throws -> FileAgentFileMutationStore {
        guard let sessiondir = environment.sessiondir(
            sessionID: sessionID
        ) else {
            throw AgentFileMutationRuntimeError.durableStorageRequired
        }

        return FileAgentFileMutationStore(
            sessionID: sessionID,
            mutationdir: sessiondir.appendingPathComponent(
                "mutations",
                isDirectory: true
            )
        )
    }

    func fileMutationRecorder(
        sessionID: String,
        environment: AgentRuntimeEnvironment,
        artifacts: (any AgentArtifactStore)? = nil,
        policy: AgentFileMutationPolicy = .normal
    ) throws -> AgentFileMutationRecorder {
        guard let sessiondir = environment.sessiondir(
            sessionID: sessionID
        ) else {
            throw AgentFileMutationRuntimeError.durableStorageRequired
        }

        let mutationdir = sessiondir.appendingPathComponent(
            "mutations",
            isDirectory: true
        )

        let store = FileAgentFileMutationStore(
            sessionID: sessionID,
            mutationdir: mutationdir
        )

        return AgentFileMutationRecorder(
            sessionID: sessionID,
            store: store,
            artifacts: artifacts,
            backups: AgentWriteBackupStore(
                mutationdir: mutationdir
            ),
            policy: policy
        )
    }
}

public enum AgentFileMutationRuntimeError: Error, Sendable, LocalizedError {
    case durableStorageRequired

    public var errorDescription: String? {
        switch self {
        case .durableStorageRequired:
            return "File mutation recording requires durable Agentic session storage."
        }
    }
}
