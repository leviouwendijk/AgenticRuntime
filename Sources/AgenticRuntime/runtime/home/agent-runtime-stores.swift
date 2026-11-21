import Agentic
import AgenticIntents
import Foundation

public struct AgentRuntimeStores: Sendable {
    public let historyStore: (any AgentHistoryStore)?
    public let sessionMetadataStore: (any AgentSessionMetadataStore)?
    public let approvalEventStore: (any AgentApprovalEventStore)?
    public let artifactStore: (any AgentArtifactStore)?
    /// Deferred tool calls; nil when the session is not durable.
    public let intents: Intents.Manager?
    public let eventSinks: [any Run.EventSink]
    public let sessionsdir: URL?
    public let transcriptsdir: URL?
    public let approvalsdir: URL?
    public let artifactsdir: URL?
    public let intentsdir: URL?

    public init(
        historyStore: (any AgentHistoryStore)? = nil,
        sessionMetadataStore: (any AgentSessionMetadataStore)? = nil,
        approvalEventStore: (any AgentApprovalEventStore)? = nil,
        artifactStore: (any AgentArtifactStore)? = nil,
        intents: Intents.Manager? = nil,
        eventSinks: [any Run.EventSink] = [],
        sessionsdir: URL? = nil,
        transcriptsdir: URL? = nil,
        approvalsdir: URL? = nil,
        artifactsdir: URL? = nil,
        intentsdir: URL? = nil
    ) {
        self.historyStore = historyStore
        self.sessionMetadataStore = sessionMetadataStore
        self.approvalEventStore = approvalEventStore
        self.artifactStore = artifactStore
        self.intents = intents
        self.eventSinks = eventSinks
        self.sessionsdir = sessionsdir
        self.transcriptsdir = transcriptsdir
        self.approvalsdir = approvalsdir
        self.artifactsdir = artifactsdir
        self.intentsdir = intentsdir
    }
}
