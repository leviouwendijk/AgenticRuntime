import Agentic
import Foundation
import Path

public struct AgentRuntimeStoreResolver: Sendable {
    public let environment: AgentRuntimeEnvironment

    public init(
        environment: AgentRuntimeEnvironment
    ) {
        self.environment = environment
    }

    public func resolveStores(
        sessionID: String
    ) throws -> AgentRuntimeStores {
        let locations = environment.storageLocations()

        guard environment.sessionStorageMode.isDurable else {
            return .init()
        }

        try environment.createSessionDirectories(
            sessionID: sessionID
        )

        let historyStore = locations.sessionsdir.map {
            FileHistoryStore(
                sessionsdir: $0
            ) as any AgentHistoryStore
        }

        let sessionMetadataStore = locations.sessionsdir.map {
            FileSessionMetadataStore(
                sessionsdir: $0
            ) as any AgentSessionMetadataStore
        }

        let approvalEventStore = try approvalEventStore(
            sessionID: sessionID
        )

        let artifactStore = try artifactStore(
            sessionID: sessionID
        )

#if AGENTIC_ENABLE_DEFERRED_INTENTS
        let preparedIntentStore = try preparedIntentStore()
#else
        // Deferred queue intentionally not installed. Conversation checkpoints remain enabled.
        let preparedIntentStore: (any PreparedIntentStore)? = nil
#endif

        let eventSinks =
            try transcriptEventSinks(
                sessionID: sessionID
            )
            + approvalEventSinks(
                sessionID: sessionID,
                approvalEventStore: approvalEventStore
            )

        return .init(
            historyStore: historyStore,
            sessionMetadataStore: sessionMetadataStore,
            approvalEventStore: approvalEventStore,
            artifactStore: artifactStore,
            preparedIntentStore: preparedIntentStore,
            eventSinks: eventSinks,
            sessionsdir: locations.sessionsdir,
            transcriptsdir: locations.transcriptsdir,
            approvalsdir: locations.approvalsdir,
            artifactsdir: locations.artifactsdir,
            preparedintentsdir: locations.preparedintentsdir
        )
    }
}

private extension AgentRuntimeStoreResolver {
    func transcriptEventSinks(
        sessionID: String
    ) throws -> [any Run.EventSink] {
        guard let transcriptfile = environment.transcriptfile(
            sessionID: sessionID
        ) else {
            return []
        }

        try PathCreation.parent(
            of: transcriptfile
        )

        let store = FileTranscriptStore(
            fileURL: transcriptfile
        )

        return [
            AgentTranscriptRecorder(
                store: store
            )
        ]
    }

    func approvalEventStore(
        sessionID: String
    ) throws -> (any AgentApprovalEventStore)? {
        guard let approvalsfile = environment.approvalsfile(
            sessionID: sessionID
        ) else {
            return nil
        }

        try PathCreation.parent(
            of: approvalsfile
        )

        return FileApprovalEventStore(
            fileURL: approvalsfile
        )
    }

    func artifactStore(
        sessionID: String
    ) throws -> (any AgentArtifactStore)? {
        guard let artifactdir = environment.artifactdir(
            sessionID: sessionID
        ) else {
            return nil
        }

        try PathCreation.directory(
            at: artifactdir
        )

        return FileAgentArtifactStore(
            sessionID: sessionID,
            artifactdir: artifactdir
        )
    }

#if AGENTIC_ENABLE_DEFERRED_INTENTS
    func preparedIntentStore() throws -> (any PreparedIntentStore)? {
        guard let preparedIntentsdir = environment.preparedintentsdir() else {
            return nil
        }

        try PathCreation.directory(
            at: preparedIntentsdir
        )

        return FilePreparedIntentStore(
            preparedIntentsdir: preparedIntentsdir
        )
    }
#endif // AGENTIC_ENABLE_DEFERRED_INTENTS

    func approvalEventSinks(
        sessionID: String,
        approvalEventStore: (any AgentApprovalEventStore)?
    ) -> [any Run.EventSink] {
        guard let approvalEventStore else {
            return []
        }

        return [
            AgentApprovalRecorder(
                sessionID: sessionID,
                store: approvalEventStore
            )
        ]
    }
}
