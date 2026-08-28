import Agentic
import AgenticExecution
import Foundation

public struct AgentSessionSummary: Sendable, Codable, Hashable, Identifiable {
    public let metadata: AgentSessionMetadata
    public let hasCheckpoint: Bool
    public let hasTranscript: Bool
    public let hasApprovals: Bool
    public let artifactCount: Int
    public let preparedIntentCount: Int

    public init(
        metadata: AgentSessionMetadata,
        hasCheckpoint: Bool,
        hasTranscript: Bool,
        hasApprovals: Bool,
        artifactCount: Int,
        preparedIntentCount: Int = 0
    ) {
        self.metadata = metadata
        self.hasCheckpoint = hasCheckpoint
        self.hasTranscript = hasTranscript
        self.hasApprovals = hasApprovals
        self.artifactCount = artifactCount
        self.preparedIntentCount = preparedIntentCount
    }

    public var id: String {
        metadata.sessionID
    }
}

public struct AgentSessionInspection: Sendable, Codable, Hashable {
    public let summary: AgentSessionSummary
    public let transcriptEventCount: Int
    public let approvalEventCount: Int
    public let artifactCount: Int
    public let preparedIntentCount: Int
    public let childBranchCount: Int

    public init(
        summary: AgentSessionSummary,
        transcriptEventCount: Int,
        approvalEventCount: Int,
        artifactCount: Int? = nil,
        preparedIntentCount: Int? = nil,
        childBranchCount: Int
    ) {
        self.summary = summary
        self.transcriptEventCount = transcriptEventCount
        self.approvalEventCount = approvalEventCount
        self.artifactCount = artifactCount ?? summary.artifactCount
        self.preparedIntentCount = preparedIntentCount ?? summary.preparedIntentCount
        self.childBranchCount = childBranchCount
    }
}

public enum AgentSessionCatalogError: Error, Sendable, LocalizedError {
    case durableStorageRequired
    case sessionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .durableStorageRequired:
            return "Session catalog operations require durable Agentic storage."

        case .sessionNotFound(let sessionID):
            return "No Agentic session exists for sessionID '\(sessionID)'."
        }
    }
}

public struct AgentSessionCatalog: Sendable {
    public let environment: AgentRuntimeEnvironment

    public init(
        environment: AgentRuntimeEnvironment
    ) {
        self.environment = environment
    }

    public func listSessions(
        statuses: [AgentSessionStatus] = [],
        includeArchived: Bool = false
    ) throws -> [AgentSessionSummary] {
        guard let sessionsdir = environment.sessionsdir() else {
            throw AgentSessionCatalogError.durableStorageRequired
        }

        guard FileManager.default.fileExists(
            atPath: sessionsdir.path
        ) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionsdir,
            includingPropertiesForKeys: [
                .isDirectoryKey
            ],
            options: [
                .skipsHiddenFiles
            ]
        )

        let summaries = try urls.compactMap { url -> AgentSessionSummary? in
            guard try isDirectory(url) else {
                return nil
            }

            let sessionID = url.lastPathComponent
            let metadata = try loadMetadata(
                sessionID: sessionID
            ) ?? AgentSessionMetadata(
                sessionID: sessionID,
                workspaceAttached: environment.workspace != nil
            )

            guard includeArchived || metadata.status != .archived else {
                return nil
            }

            if !statuses.isEmpty,
               !statuses.contains(metadata.status) {
                return nil
            }

            return summary(
                metadata: metadata
            )
        }

        return summaries.sorted { lhs, rhs in
            if lhs.metadata.updatedAt == rhs.metadata.updatedAt {
                return lhs.id < rhs.id
            }

            return lhs.metadata.updatedAt > rhs.metadata.updatedAt
        }
    }

    public func loadSession(
        sessionID: String
    ) throws -> AgentSessionSummary {
        if let metadata = try loadMetadata(
            sessionID: sessionID
        ) {
            return summary(
                metadata: metadata
            )
        }

        guard let sessiondir = environment.sessiondir(
            sessionID: sessionID
        ),
              FileManager.default.fileExists(
                atPath: sessiondir.path
              )
        else {
            throw AgentSessionCatalogError.sessionNotFound(
                sessionID
            )
        }

        return summary(
            metadata: .init(
                sessionID: sessionID,
                workspaceAttached: environment.workspace != nil
            )
        )
    }

    public func inspectSession(
        sessionID: String
    ) async throws -> AgentSessionInspection {
        let session = try loadSession(
            sessionID: sessionID
        )
        let transcriptEvents = try await loadTranscript(
            sessionID: sessionID
        )
        let approvalEvents = try await loadApprovals(
            sessionID: sessionID
        )
        let artifacts = try await listArtifacts(
            sessionID: sessionID
        )
        let preparedIntents = try await listPreparedIntents(
            sessionID: sessionID,
            includeExpired: true
        )
        let branches = try listBranches(
            parentSessionID: sessionID
        )

        return .init(
            summary: session,
            transcriptEventCount: transcriptEvents.count,
            approvalEventCount: approvalEvents.count,
            artifactCount: artifacts.count,
            preparedIntentCount: preparedIntents.count,
            childBranchCount: branches.count
        )
    }

    public func listBranches(
        parentSessionID: String
    ) throws -> [AgentSessionSummary] {
        try listSessions(
            includeArchived: true
        ).filter { summary in
            summary.metadata.branch?.parentSessionID == parentSessionID
        }
    }

    public func updateSession(
        sessionID: String,
        title: String? = nil,
        status: AgentSessionStatus? = nil,
        metadata extraMetadata: [String: String] = [:]
    ) throws -> AgentSessionMetadata {
        var metadata = try loadMetadata(
            sessionID: sessionID
        ) ?? AgentSessionMetadata(
            sessionID: sessionID,
            workspaceAttached: environment.workspace != nil
        )

        if let title {
            metadata.title = title
        }

        if let status {
            metadata.status = status
        }

        if !extraMetadata.isEmpty {
            metadata.metadata.merge(
                extraMetadata,
                uniquingKeysWith: { _, new in
                    new
                }
            )
        }

        metadata.updatedAt = Date()

        try metadataStore()?.save(
            metadata
        )

        return metadata
    }

    public func loadTranscript(
        sessionID: String
    ) async throws -> [AgentTranscriptEvent] {
        guard
            let transcriptfile = environment.transcriptfile(
                sessionID: sessionID
            )
        else {
            return []
        }

        return try await FileTranscriptStore(
            fileURL: transcriptfile
        ).loadEvents()
    }

    public func loadApprovals(
        sessionID: String
    ) async throws -> [AgentApprovalEvent] {
        guard let approvalsfile = environment.approvalsfile(
            sessionID: sessionID
        ) else {
            return []
        }

        return try await FileApprovalEventStore(
            fileURL: approvalsfile
        ).loadEvents()
    }

    public func listArtifacts(
        sessionID: String,
        kinds: [AgentArtifactKind] = [],
        latestFirst: Bool = true,
        limit: Int? = nil
    ) async throws -> [AgentArtifact] {
        _ = try loadSession(
            sessionID: sessionID
        )

        guard let store = artifactStore(
            sessionID: sessionID
        ) else {
            return []
        }

        return try await store.list(
            kinds: kinds,
            latestFirst: latestFirst,
            limit: limit
        )
    }

    public func loadArtifact(
        sessionID: String,
        id: String
    ) async throws -> AgentArtifactRecord {
        _ = try loadSession(
            sessionID: sessionID
        )

        guard let store = artifactStore(
            sessionID: sessionID
        ) else {
            throw AgentArtifactError.artifactNotFound(
                id
            )
        }

        guard let record = try await store.load(
            id: id
        ) else {
            throw AgentArtifactError.artifactNotFound(
                id
            )
        }

        return record
    }

    public func listPreparedIntents(
        sessionID: String,
        statuses: [PreparedIntentStatus] = [],
        actionType: String? = nil,
        includeExpired: Bool = false,
        limit: Int? = nil
    ) async throws -> [PreparedIntent] {
        _ = try loadSession(
            sessionID: sessionID
        )

        guard let manager = preparedIntentManager() else {
            return []
        }

        let intents = try await manager.list(
            statuses: statuses,
            sessionID: sessionID,
            actionType: actionType,
            includeExpired: includeExpired
        )

        guard let limit else {
            return intents
        }

        return Array(
            intents.prefix(
                max(
                    0,
                    limit
                )
            )
        )
    }

    public func loadPreparedIntent(
        sessionID: String,
        id: PreparedIntentIdentifier
    ) async throws -> PreparedIntent {
        _ = try loadSession(
            sessionID: sessionID
        )

        guard let manager = preparedIntentManager() else {
            throw PreparedIntentError.intentNotFound(
                id
            )
        }

        let intent = try await manager.get(
            id
        )

        guard intent.sessionID == sessionID else {
            throw PreparedIntentError.intentNotFound(
                id
            )
        }

        return intent
    }
}

private extension AgentSessionCatalog {
    func metadataStore() -> FileSessionMetadataStore? {
        guard let sessionsdir = environment.sessionsdir() else {
            return nil
        }

        return FileSessionMetadataStore(
            sessionsdir: sessionsdir
        )
    }

    func loadMetadata(
        sessionID: String
    ) throws -> AgentSessionMetadata? {
        try metadataStore()?.load(
            sessionID: sessionID
        )
    }

    func summary(
        metadata: AgentSessionMetadata
    ) -> AgentSessionSummary {
        let sessionID = metadata.sessionID

        return .init(
            metadata: metadata,
            hasCheckpoint: exists(
                environment.checkpointfile(
                    sessionID: sessionID
                )
            ),
            hasTranscript: exists(
                environment.transcriptfile(
                    sessionID: sessionID
                )
            ),
            hasApprovals: exists(
                environment.approvalsfile(
                    sessionID: sessionID
                )
            ),
            artifactCount: artifactCount(
                sessionID: sessionID
            ),
            preparedIntentCount: preparedIntentCount(
                sessionID: sessionID
            )
        )
    }

    func artifactStore(
        sessionID: String
    ) -> FileAgentArtifactStore? {
        guard let artifactdir = environment.artifactdir(
            sessionID: sessionID
        ) else {
            return nil
        }

        return FileAgentArtifactStore(
            sessionID: sessionID,
            artifactdir: artifactdir
        )
    }

    func preparedIntentManager() -> PreparedIntentManager? {
        guard let preparedIntentsdir = environment.preparedintentsdir() else {
            return nil
        }

        return PreparedIntentManager(
            store: FilePreparedIntentStore(
                preparedIntentsdir: preparedIntentsdir
            )
        )
    }

    func artifactCount(
        sessionID: String
    ) -> Int {
        guard let url = environment.artifactdir(
            sessionID: sessionID
        ),
              FileManager.default.fileExists(
                atPath: url.path
              ),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey
                ],
                options: [
                    .skipsHiddenFiles
                ]
              )
        else {
            return 0
        }

        return urls.filter { url in
            guard (try? isDirectory(url)) == true else {
                return false
            }

            return FileManager.default.fileExists(
                atPath: url
                    .appendingPathComponent(
                        "artifact.json",
                        isDirectory: false
                    )
                    .path
            )
        }.count
    }

    func preparedIntentCount(
        sessionID: String
    ) -> Int {
        guard let url = environment.preparedintentsdir(),
              FileManager.default.fileExists(
                atPath: url.path
              ),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [
                    .skipsHiddenFiles
                ]
              )
        else {
            return 0
        }

        return urls.filter { url in
            guard url.pathExtension == "json",
                  let data = try? Data(
                    contentsOf: url
                  ),
                  !data.isEmpty,
                  let intent = try? JSONDecoder().decode(
                    PreparedIntent.self,
                    from: data
                  )
            else {
                return false
            }

            return intent.sessionID == sessionID
        }.count
    }

    func exists(
        _ url: URL?
    ) -> Bool {
        guard let url else {
            return false
        }

        return FileManager.default.fileExists(
            atPath: url.path
        )
    }

    func isDirectory(
        _ url: URL
    ) throws -> Bool {
        let values = try url.resourceValues(
            forKeys: [
                .isDirectoryKey
            ]
        )

        return values.isDirectory == true
    }
}
