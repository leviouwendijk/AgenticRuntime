import Agentic
import Foundation

public struct AgentSessionMetadata: Sendable, Codable, Hashable, Identifiable {
    public var sessionID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String?
    public var status: AgentSessionStatus
    public var profileID: String?
    public var workspaceAttached: Bool
    public var branch: AgentSessionBranch?
    public var metadata: [String: String]

    public init(
        sessionID: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String? = nil,
        status: AgentSessionStatus = .active,
        profileID: String? = nil,
        workspaceAttached: Bool = false,
        branch: AgentSessionBranch? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.status = status
        self.profileID = profileID
        self.workspaceAttached = workspaceAttached
        self.branch = branch
        self.metadata = metadata
    }

    public var id: String {
        sessionID
    }
}

public extension AgentSessionMetadata {
    func touching(
        updatedAt: Date = Date()
    ) -> Self {
        var copy = self
        copy.updatedAt = updatedAt
        return copy
    }

    func withStatus(
        _ status: AgentSessionStatus,
        updatedAt: Date = Date()
    ) -> Self {
        var copy = self
        copy.status = status
        copy.updatedAt = updatedAt
        return copy
    }

    func withSessionID(
        _ sessionID: String
    ) -> Self {
        var copy = self
        copy.sessionID = sessionID
        return copy
    }
}
