import Workspace
import Foundation
import Path

/// A session's changes on top of its base Workspace: leased roots,
/// deny-only restrictions, and the working directory. The base stays as
/// configured; everything here can be listed and revoked.
public struct WorkspaceAccessLeases:
    Sendable,
    Codable,
    Hashable
{
    public let values: [WorkspaceAccessLease]
    public let restrictions: [WorkspaceAccessRestriction]
    public let directory: WorkspaceDirectory?

    public init() {
        self.values = []
        self.restrictions = []
        self.directory = nil
    }

    public init(
        values: [WorkspaceAccessLease],
        restrictions: [WorkspaceAccessRestriction] = [],
        directory: WorkspaceDirectory? = nil
    ) throws {
        var ids: Set<String> = []

        for id in values.map(\.id) + restrictions.map(\.id) {
            guard ids.insert(id).inserted else {
                throw WorkspaceAccessLeasesError
                    .duplicate_lease(
                        id
                    )
            }
        }

        self.values = values
        self.restrictions = restrictions
        self.directory = directory
    }

    private init(
        validatedValues: [WorkspaceAccessLease],
        restrictions: [WorkspaceAccessRestriction],
        directory: WorkspaceDirectory?
    ) {
        self.values = validatedValues
        self.restrictions = restrictions
        self.directory = directory
    }

    private enum CodingKeys: String, CodingKey {
        case values
        case restrictions
        case directory
    }

    public init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        try self.init(
            values: container.decodeIfPresent(
                [WorkspaceAccessLease].self,
                forKey: .values
            ) ?? [],
            restrictions: container.decodeIfPresent(
                [WorkspaceAccessRestriction].self,
                forKey: .restrictions
            ) ?? [],
            directory: container.decodeIfPresent(
                WorkspaceDirectory.self,
                forKey: .directory
            )
        )
    }

    public func active(
        for turnID: String?,
        at date: Date = Date()
    ) -> [WorkspaceAccessLease] {
        values.filter { lease in
            lease.isActive(
                for: turnID,
                at: date
            )
        }
    }

    /// Roots of active ask leases that no active grant lease covers: a
    /// call refused there asks the operator.
    public func askRoots(
        for turnID: String?,
        at date: Date = Date()
    ) -> Set<PathAccessRootIdentifier> {
        let active = active(for: turnID, at: date)
        let granted = Set(active.filter { $0.access == .grant }.map(\.request.rootID))
        return Set(
            active
                .filter { $0.access == .ask && !granted.contains($0.request.rootID) }
                .map { PathAccessRootIdentifier(rawValue: $0.request.rootID) }
        )
    }

    /// The base with active leases installed, then restrictions on roots
    /// still present, then the working directory's root as the default.
    public func effectiveWorkspace(
        base: Workspace?,
        turnID: String?,
        at date: Date = Date()
    ) throws -> Workspace? {
        let active = active(
            for: turnID,
            at: date
        )

        guard !active.isEmpty || !restrictions.isEmpty || directory != nil else {
            return base
        }
        guard var workspace = base else {
            throw WorkspaceAccessLeasesError
                .base_workspace_required
        }

        for lease in active {
            try lease.install(
                into: &workspace
            )
        }

        for restriction in restrictions {
            let root = PathAccessRootIdentifier(
                rawValue: restriction.rootID
            )

            guard workspace.root(identifier: root) != nil else {
                continue
            }

            try workspace.restrict(
                root,
                denying: [
                    restriction.rule,
                ]
            )
        }

        if let directory,
           workspace.root(identifier: directory.root) != nil
        {
            try workspace.makeDefault(
                directory.root
            )
        }

        return workspace
    }

    /// The context tools resolve relative paths against: the working
    /// directory when it is still inside its root, else the default root.
    public func context(
        in workspace: Workspace,
        execution: WorkspaceExecution
    ) throws -> WorkspaceContext {
        guard let directory,
              let root = workspace.root(identifier: directory.root),
              let path = try? DescendantPath(
                  StandardPath(
                      fileURL: URL(
                          fileURLWithPath: directory.path,
                          isDirectory: true
                      ),
                      terminalHint: .directory,
                      inferFileType: false
                  ),
                  from: root.scope.root
              )
        else {
            return try workspace.context(
                execution: execution
            )
        }

        return try workspace.context(
            at: path,
            rootIdentifier: root.id,
            execution: execution
        )
    }

    public func activating(
        _ lease: WorkspaceAccessLease,
        baseWorkspace: Workspace?,
        turnID: String?,
        at date: Date = Date()
    ) throws -> Self {
        if lease.lifetime == .turn,
           lease.sourceTurnID != turnID
        {
            throw WorkspaceAccessLeasesError
                .turn_context_mismatch(
                    expected: lease.sourceTurnID,
                    actual: turnID
                )
        }

        let next = try Self(
            values: values + [
                lease,
            ],
            restrictions: restrictions,
            directory: directory
        )

        _ = try next.effectiveWorkspace(
            base: baseWorkspace,
            turnID: turnID,
            at: date
        )

        return next
    }

    public func restricting(
        _ restriction: WorkspaceAccessRestriction,
        baseWorkspace: Workspace?,
        turnID: String?,
        at date: Date = Date()
    ) throws -> Self {
        guard let workspace = try effectiveWorkspace(
            base: baseWorkspace,
            turnID: turnID,
            at: date
        ),
            workspace.root(
                identifier: PathAccessRootIdentifier(
                    rawValue: restriction.rootID
                )
            ) != nil
        else {
            throw WorkspaceAccessLeasesError
                .root_not_found(
                    restriction.rootID
                )
        }

        return try Self(
            values: values,
            restrictions: restrictions + [
                restriction,
            ],
            directory: directory
        )
    }

    /// Moves the working directory. `nil` returns to the base's default
    /// root. The directory must lie inside a root and be listable there;
    /// this never grants access, it only changes where relative paths
    /// resolve.
    public func changingDirectory(
        to path: String?,
        baseWorkspace: Workspace?,
        turnID: String?,
        at date: Date = Date()
    ) throws -> Self {
        guard let path else {
            return .init(
                validatedValues: values,
                restrictions: restrictions,
                directory: nil
            )
        }

        let current = try Self(
            values: values,
            restrictions: restrictions
        )
        guard let workspace = try current.effectiveWorkspace(
            base: baseWorkspace,
            turnID: turnID,
            at: date
        ) else {
            throw WorkspaceAccessLeasesError
                .base_workspace_required
        }

        let url = URL(
            fileURLWithPath: path,
            isDirectory: true
        )
        .standardizedFileURL
        let standard = StandardPath(
            fileURL: url,
            terminalHint: .directory,
            inferFileType: false
        )
        let containing = workspace.roots
            .compactMap { root -> (PathAccessRoot, DescendantPath)? in
                (try? DescendantPath(standard, from: root.scope.root)).map { (root, $0) }
            }
            .max {
                $0.0.scope.root.segments.count < $1.0.scope.root.segments.count
            }

        guard let (root, descendant) = containing else {
            throw WorkspaceAccessLeasesError
                .directory_outside_workspace(
                    url.path
                )
        }

        _ = try workspace.authorize(
            rootIdentifier: root.id,
            path: descendant,
            capability: .list,
            at: date
        )

        return .init(
            validatedValues: values,
            restrictions: restrictions,
            directory: .init(
                root: root.id,
                path: url.path
            )
        )
    }

    /// Removes a lease or a restriction. Restrictions on a revoked lease's
    /// root go with it, and so does a working directory under it.
    public func revoking(
        _ id: String
    ) throws -> Self {
        if let lease = values.first(where: { $0.id == id }) {
            let remaining = values.filter { $0.id != id }
            let rootStays = remaining.contains {
                $0.request.rootID == lease.request.rootID
            }

            return .init(
                validatedValues: remaining,
                restrictions: rootStays
                    ? restrictions
                    : restrictions.filter { $0.rootID != lease.request.rootID },
                directory: !rootStays && directory?.root.rawValue == lease.request.rootID
                    ? nil
                    : directory
            )
        }

        guard restrictions.contains(where: { $0.id == id }) else {
            throw WorkspaceAccessLeasesError
                .lease_not_found(
                    id
                )
        }

        return .init(
            validatedValues: values,
            restrictions: restrictions.filter { $0.id != id },
            directory: directory
        )
    }

    public func endingTurn(
        _ turnID: String
    ) -> Self {
        .init(
            validatedValues: values.filter { lease in
                lease.lifetime != .turn
                    || lease.sourceTurnID != turnID
            },
            restrictions: restrictions,
            directory: directory
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
            },
            restrictions: restrictions,
            directory: directory
        )
    }
}

/// A deny rule the operator put on a root, e.g. `:path deny '**/*.sql'`.
public struct WorkspaceAccessRestriction:
    Sendable,
    Codable,
    Hashable,
    Identifiable
{
    public let id: String
    public let rootID: String
    /// The pattern as the operator typed it.
    public let pattern: String
    public let rule: PathAccessRule

    public init(
        id: String = UUID().uuidString,
        rootID: String,
        pattern: String,
        rule: PathAccessRule
    ) throws {
        guard rule.decision.isDenied else {
            throw WorkspaceAccessLeasesError
                .restriction_must_deny(
                    pattern
                )
        }

        self.id = id
        self.rootID = rootID
        self.pattern = pattern
        self.rule = rule
    }
}

/// Where relative paths resolve: a directory inside `root`.
public struct WorkspaceDirectory:
    Sendable,
    Codable,
    Hashable
{
    public let root: PathAccessRootIdentifier
    /// Absolute.
    public let path: String

    public init(
        root: PathAccessRootIdentifier,
        path: String
    ) {
        self.root = root
        self.path = path
    }
}

public enum WorkspaceAccessLeasesError:
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
    case lease_not_found(String)
    case root_not_found(String)
    case restriction_must_deny(String)
    case directory_outside_workspace(String)

    public var errorDescription: String? {
        switch self {
        case .duplicate_lease(let id):
            return "Workspace access lease '\(id)' is already active."

        case .base_workspace_required:
            return "Temporary workspace access requires an attached base workspace."

        case .turn_context_mismatch(let expected, let actual):
            return "Turn-scoped workspace access lease belongs to turn '\(expected ?? "none")', not '\(actual ?? "none")'."

        case .lease_not_found(let id):
            return "No workspace lease or restriction '\(id)'."

        case .root_not_found(let id):
            return "Workspace root '\(id)' is not installed."

        case .restriction_must_deny(let pattern):
            return "Restriction '\(pattern)' must deny paths."

        case .directory_outside_workspace(let path):
            return "'\(path)' is outside every workspace root; add it with :path add first."
        }
    }
}
