import Agentic
import AgenticIO
import AgenticWorkspace
import Foundation

public struct AgentWorkspaceAccessLease:
    Sendable,
    Codable,
    Hashable,
    Identifiable
{
    public let id: String
    public let overlay: WorkspaceAccessOverlay
    public let lifetime: PathGrantLifetime
    public let activatedAt: Date
    public let expiresAt: Date?
    public let sourceTurnID: String?
    public let preparedIntentID: PreparedIntentIdentifier?

    public init(
        id: String = UUID().uuidString,
        overlay: WorkspaceAccessOverlay,
        lifetime: PathGrantLifetime,
        durationSeconds: TimeInterval? = nil,
        activatedAt: Date = Date(),
        sourceTurnID: String? = nil,
        preparedIntentID: PreparedIntentIdentifier? = nil
    ) throws {
        let expiresAt: Date?

        if let durationSeconds {
            guard durationSeconds.isFinite,
                  durationSeconds >= 0
            else {
                throw AgentWorkspaceAccessLeaseError
                    .invalid_duration(
                        durationSeconds
                    )
            }

            expiresAt = activatedAt.addingTimeInterval(
                durationSeconds
            )
        } else {
            expiresAt = nil
        }

        try self.init(
            id: id,
            overlay: overlay,
            lifetime: lifetime,
            activatedAt: activatedAt,
            expiresAt: expiresAt,
            sourceTurnID: sourceTurnID,
            preparedIntentID: preparedIntentID
        )
    }

    private init(
        id: String,
        overlay: WorkspaceAccessOverlay,
        lifetime: PathGrantLifetime,
        activatedAt: Date,
        expiresAt: Date?,
        sourceTurnID: String?,
        preparedIntentID: PreparedIntentIdentifier?
    ) throws {
        let id = id.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !id.isEmpty else {
            throw AgentWorkspaceAccessLeaseError.empty_id
        }

        let sourceTurnID = sourceTurnID?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if lifetime == .turn {
            guard let sourceTurnID,
                  !sourceTurnID.isEmpty
            else {
                throw AgentWorkspaceAccessLeaseError
                    .turn_lifetime_requires_turn_id
            }
        }

        if let expiresAt {
            let duration = expiresAt.timeIntervalSince(
                activatedAt
            )

            guard duration.isFinite,
                  duration >= 0
            else {
                throw AgentWorkspaceAccessLeaseError
                    .invalid_duration(
                        duration
                    )
            }
        }

        self.id = id
        self.overlay = overlay
        self.lifetime = lifetime
        self.activatedAt = activatedAt
        self.expiresAt = expiresAt
        self.sourceTurnID = sourceTurnID
        self.preparedIntentID = preparedIntentID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case overlay
        case lifetime
        case activatedAt
        case expiresAt
        case sourceTurnID
        case preparedIntentID
    }

    public init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        try self.init(
            id: container.decode(
                String.self,
                forKey: .id
            ),
            overlay: container.decode(
                WorkspaceAccessOverlay.self,
                forKey: .overlay
            ),
            lifetime: container.decode(
                PathGrantLifetime.self,
                forKey: .lifetime
            ),
            activatedAt: container.decode(
                Date.self,
                forKey: .activatedAt
            ),
            expiresAt: container.decodeIfPresent(
                Date.self,
                forKey: .expiresAt
            ),
            sourceTurnID: container.decodeIfPresent(
                String.self,
                forKey: .sourceTurnID
            ),
            preparedIntentID: container.decodeIfPresent(
                PreparedIntentIdentifier.self,
                forKey: .preparedIntentID
            )
        )
    }

    public func isActive(
        for turnID: String?,
        at date: Date = Date()
    ) -> Bool {
        if let expiresAt,
           date >= expiresAt
        {
            return false
        }

        switch lifetime {
        case .turn:
            return sourceTurnID == turnID

        case .session:
            return true
        }
    }

    public func effectiveOverlay() throws -> WorkspaceAccessOverlay {
        try WorkspaceAccessOverlay(
            roots: try overlay.roots.map { grantedRoot in
                try .init(
                    root: grantedRoot.root,
                    grant: effectiveGrant(
                        grantedRoot.grant
                    ),
                    selection: grantedRoot.selection
                )
            },
            grants: overlay.grants.map(
                effectiveGrant
            )
        )
    }
}

private extension AgentWorkspaceAccessLease {
    func effectiveGrant(
        _ grant: PathGrant
    ) -> PathGrant {
        let effectiveExpiresAt: Date?

        switch (
            grant.expiresAt,
            expiresAt
        ) {
        case (.some(let grantExpiry), .some(let leaseExpiry)):
            effectiveExpiresAt = min(
                grantExpiry,
                leaseExpiry
            )

        case (.some(let grantExpiry), .none):
            effectiveExpiresAt = grantExpiry

        case (.none, .some(let leaseExpiry)):
            effectiveExpiresAt = leaseExpiry

        case (.none, .none):
            effectiveExpiresAt = nil
        }

        return .init(
            id: grant.id,
            rootID: grant.rootID,
            mode: grant.mode,
            capabilities: grant.capabilities,
            allowedTools: grant.allowedTools,
            reason: grant.reason,
            expiresAt: effectiveExpiresAt,
            sourcePreparedIntentID:
                grant.sourcePreparedIntentID
                ?? preparedIntentID,
            metadata: grant.metadata
        )
    }
}

public enum AgentWorkspaceAccessLeaseError:
    Error,
    Sendable,
    Hashable,
    LocalizedError
{
    case empty_id
    case turn_lifetime_requires_turn_id
    case invalid_duration(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .empty_id:
            return "Workspace access lease identifier cannot be empty."

        case .turn_lifetime_requires_turn_id:
            return "Turn-scoped workspace access lease requires a source turn identifier."

        case .invalid_duration(let duration):
            return "Workspace access lease duration '\(duration)' must be finite and non-negative."
        }
    }
}
