import AgenticWorkspace
import Foundation

public struct AgentWorkspaceAccessLeases:
    Sendable,
    Codable,
    Hashable
{
    public let values: [AgentWorkspaceAccessLease]

    public init() {
        self.values = []
    }

    public init(
        values: [AgentWorkspaceAccessLease]
    ) throws {
        var ids: Set<String> = []

        for lease in values {
            guard ids.insert(lease.id).inserted else {
                throw AgentWorkspaceAccessLeasesError
                    .duplicate_lease(
                        lease.id
                    )
            }
        }

        self.values = values
    }

    private init(
        validatedValues: [AgentWorkspaceAccessLease]
    ) {
        self.values = validatedValues
    }

    private enum CodingKeys: String, CodingKey {
        case values
    }

    public init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        try self.init(
            values: container.decodeIfPresent(
                [AgentWorkspaceAccessLease].self,
                forKey: .values
            ) ?? []
        )
    }

    public func active(
        for turnID: String?,
        at date: Date = Date()
    ) -> [AgentWorkspaceAccessLease] {
        values.filter { lease in
            lease.isActive(
                for: turnID,
                at: date
            )
        }
    }

    public func effectiveWorkspace(
        base: AgentWorkspace?,
        turnID: String?,
        at date: Date = Date()
    ) throws -> AgentWorkspace? {
        let active = active(
            for: turnID,
            at: date
        )

        guard !active.isEmpty else {
            return base
        }
        guard let base else {
            throw AgentWorkspaceAccessLeasesError
                .base_workspace_required
        }

        return try base.applying(
            try active.map { lease in
                try lease.effectiveOverlay()
            }
        )
    }

    public func activating(
        _ lease: AgentWorkspaceAccessLease,
        baseWorkspace: AgentWorkspace?,
        turnID: String?,
        at date: Date = Date()
    ) throws -> Self {
        if lease.lifetime == .turn,
           lease.sourceTurnID != turnID
        {
            throw AgentWorkspaceAccessLeasesError
                .turn_context_mismatch(
                    expected: lease.sourceTurnID,
                    actual: turnID
                )
        }

        let next = try Self(
            values: values + [
                lease,
            ]
        )

        _ = try next.effectiveWorkspace(
            base: baseWorkspace,
            turnID: turnID,
            at: date
        )

        return next
    }

    public func endingTurn(
        _ turnID: String
    ) -> Self {
        .init(
            validatedValues: values.filter { lease in
                lease.lifetime != .turn
                    || lease.sourceTurnID != turnID
            }
        )
    }

    public func expiring(
        at date: Date = Date()
    ) -> Self {
        .init(
            validatedValues: values.filter { lease in
                guard let expiresAt = lease.expiresAt else {
                    return true
                }

                return date < expiresAt
            }
        )
    }
}

public enum AgentWorkspaceAccessLeasesError:
    Error,
    Sendable,
    Hashable,
    LocalizedError
{
    case duplicate_lease(String)
    case base_workspace_required
    case turn_context_mismatch(
        expected: String?,
        actual: String?
    )

    public var errorDescription: String? {
        switch self {
        case .duplicate_lease(let id):
            return "Workspace access lease '\(id)' is already active."

        case .base_workspace_required:
            return "Temporary workspace access overlays require an attached base workspace."

        case .turn_context_mismatch(let expected, let actual):
            return "Turn-scoped workspace access lease belongs to turn '\(expected ?? "none")', not '\(actual ?? "none")'."
        }
    }
}
