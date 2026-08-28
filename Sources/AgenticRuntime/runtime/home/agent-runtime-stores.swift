import Agentic
import AgenticExecution
import Foundation

public struct AgentRuntimeStores: Sendable {
    public let historyStore: (any AgentHistoryStore)?
    public let sessionMetadataStore: (any AgentSessionMetadataStore)?
    public let approvalEventStore: (any AgentApprovalEventStore)?
    public let artifactStore: (any AgentArtifactStore)?
    public let preparedIntentStore: (any PreparedIntentStore)?
    public let eventSinks: [any AgentRunEventSink]
    public let sessionsdir: URL?
    public let transcriptsdir: URL?
    public let approvalsdir: URL?
    public let artifactsdir: URL?
    public let preparedintentsdir: URL?

    public init(
        historyStore: (any AgentHistoryStore)? = nil,
        sessionMetadataStore: (any AgentSessionMetadataStore)? = nil,
        approvalEventStore: (any AgentApprovalEventStore)? = nil,
        artifactStore: (any AgentArtifactStore)? = nil,
        preparedIntentStore: (any PreparedIntentStore)? = nil,
        eventSinks: [any AgentRunEventSink] = [],
        sessionsdir: URL? = nil,
        transcriptsdir: URL? = nil,
        approvalsdir: URL? = nil,
        artifactsdir: URL? = nil,
        preparedintentsdir: URL? = nil
    ) {
        self.historyStore = historyStore
        self.sessionMetadataStore = sessionMetadataStore
        self.approvalEventStore = approvalEventStore
        self.artifactStore = artifactStore
        self.preparedIntentStore = preparedIntentStore
        self.eventSinks = eventSinks
        self.sessionsdir = sessionsdir
        self.transcriptsdir = transcriptsdir
        self.approvalsdir = approvalsdir
        self.artifactsdir = artifactsdir
        self.preparedintentsdir = preparedintentsdir
    }
}
