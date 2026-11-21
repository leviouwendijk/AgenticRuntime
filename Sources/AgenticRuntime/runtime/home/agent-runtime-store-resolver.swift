import Agentic
import AgenticIntents
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

        let intents = environment.intentManager()

        let eventSinks =
            try logEventSinks(
                sessionID: sessionID
            )
            + transcriptEventSinks(
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
            intents: intents,
            eventSinks: eventSinks,
            sessionsdir: locations.sessionsdir,
            transcriptsdir: locations.transcriptsdir,
            approvalsdir: locations.approvalsdir,
            artifactsdir: locations.artifactsdir,
            intentsdir: locations.intentsdir
        )
    }
}

private extension AgentRuntimeStoreResolver {
    func logEventSinks(
        sessionID: String
    ) throws -> [any Run.EventSink] {
        guard let storage = environment.runtimeStorageLayout() else {
            return []
        }

        let store = Run.Log.Store(
            storage: storage,
            durability: try environment.home.settings().log.durability
        )

        return [
            try store.open(session: sessionID).recorder(run: sessionID)
        ]
    }

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
