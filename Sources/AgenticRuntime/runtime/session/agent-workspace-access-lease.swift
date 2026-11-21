import AgenticIO
import Workspace
import Foundation
import Path

public struct WorkspaceAccessLease:
    Sendable,
    Codable,
    Hashable,
    Identifiable
{
    public let id: String
    public let request: WorkspaceAccessRequest
    public let lifetime: WorkspaceAccessLifetime
    public let activatedAt: Date
    public let expiresAt: Date?
    public let sourceTurnID: String?
    public let origin: WorkspaceAccessOrigin
    /// `.ask`: the root exists but grants nothing; a call that needs it
    /// asks the operator, who grants it for a turn or the session.
    public let access: WorkspaceAccessMode

    public init(
        id: String = UUID().uuidString,
        request: WorkspaceAccessRequest,
        lifetime: WorkspaceAccessLifetime,
        durationSeconds: TimeInterval? = nil,
        activatedAt: Date = Date(),
        sourceTurnID: String? = nil,
        origin: WorkspaceAccessOrigin = .request,
        access: WorkspaceAccessMode = .grant
    ) throws {
        let durationSeconds = durationSeconds
            ?? request.durationSeconds
        let expiresAt: Date?

        if let durationSeconds {
            guard durationSeconds.isFinite,
                  durationSeconds >= 0
            else {
                throw WorkspaceAccessLeaseError
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
            request: request,
            lifetime: lifetime,
            activatedAt: activatedAt,
            expiresAt: expiresAt,
            sourceTurnID: sourceTurnID,
            origin: origin,
            access: access
        )
    }

    private init(
        id: String,
        request: WorkspaceAccessRequest,
        lifetime: WorkspaceAccessLifetime,
        activatedAt: Date,
        expiresAt: Date?,
        sourceTurnID: String?,
        origin: WorkspaceAccessOrigin,
        access: WorkspaceAccessMode
    ) throws {
        let id = id.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !id.isEmpty else {
            throw WorkspaceAccessLeaseError.empty_id
        }

        let sourceTurnID = sourceTurnID?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if lifetime == .turn {
            guard let sourceTurnID,
                  !sourceTurnID.isEmpty
            else {
                throw WorkspaceAccessLeaseError
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
                throw WorkspaceAccessLeaseError
                    .invalid_duration(
                        duration
                    )
            }
        }

        self.id = id
        self.request = request
        self.lifetime = lifetime
        self.activatedAt = activatedAt
        self.expiresAt = expiresAt
        self.sourceTurnID = sourceTurnID
        self.origin = origin
        self.access = access
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case request
        case lifetime
        case activatedAt
        case expiresAt
        case sourceTurnID
        case origin
        case access
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
            request: container.decode(
                WorkspaceAccessRequest.self,
                forKey: .request
            ),
            lifetime: container.decode(
                WorkspaceAccessLifetime.self,
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
            origin: container.decodeIfPresent(
                WorkspaceAccessOrigin.self,
                forKey: .origin
            ) ?? .request,
            access: container.decodeIfPresent(
                WorkspaceAccessMode.self,
                forKey: .access
            ) ?? .grant
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

    public func install(
        into workspace: inout Workspace
    ) throws {
        let rootIdentifier = PathAccessRootIdentifier(
            rawValue: request.rootID
        )
        let rootURL = URL(
            fileURLWithPath: request.rootPath,
            isDirectory: true
        )
        .standardizedFileURL
        .resolvingSymlinksInPath()

        let root = PathAccessRoot(
            id: rootIdentifier,
            label: request.label,
            scope: try PathAccessScope(
                root: rootURL,
                policy: .defaults.workspace
            ),
            isDefault: false
        )
        // A file lease grants each named file alone, never its directory.
        let scopes: [WorkspaceScope] = try request.files.map { files in
            try files.map { try .file($0) }
        } ?? [.root]
        let grants = try scopes.enumerated().map { index, scope in
            try WorkspaceGrant(
                id: WorkspaceGrantIdentifier(
                    index == 0 ? "workspace-access-\(id)" : "workspace-access-\(id)-\(index)"
                ),
                rootIdentifier: rootIdentifier,
                scope: scope,
                capabilities: Set(
                    request.capabilities
                ),
                expiresAt: expiresAt
            )
        }

        // An ask root grants nothing until the operator answers a call.
        if access == .ask {
            guard workspace.root(identifier: rootIdentifier) == nil else { return }
            _ = try workspace.install { installation in
                installation.install(root)
            }
            return
        }

        if let existing = workspace.root(
            identifier: rootIdentifier
        ) {
            guard existing.rootURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
                == rootURL
            else {
                throw WorkspaceAccessLeaseError
                    .root_identifier_conflict(
                        rootIdentifier.rawValue
                    )
            }

            for grant in grants {
                _ = try workspace.install(
                    grant
                )
            }
            return
        }

        _ = try workspace.install { installation in
            installation.install(
                root
            )
            for grant in grants {
                installation.install(
                    grant
                )
            }
        }
    }
}

/// Whether a lease grants its capabilities or asks for them call by call.
public enum WorkspaceAccessMode:
    String,
    Sendable,
    Codable,
    Hashable
{
    case grant
    case ask
}

/// Who installed a lease. Either way the change is a traced event.
public enum WorkspaceAccessOrigin:
    String,
    Sendable,
    Codable,
    Hashable
{
    /// The model asked through `io_tool_request_access` and the operator
    /// approved it.
    case request
    /// The operator added it directly, e.g. `:path add`.
    case operator_command
    /// `settings.paths.allow` in the home's `settings.frame`, at session start.
    case settings
}

public extension WorkspaceAccessLease {
    /// `label  /path · read, write · session`
    var summary: String {
        let capabilities = request.capabilities
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")
        let path = request.files.map { files in
            files.map { (request.rootPath as NSString).appendingPathComponent($0) }.joined(separator: ", ")
        } ?? request.rootPath
        let mode = access == .ask ? "ask · " : ""
        return "\(request.label)  \(path) · \(mode)\(capabilities) · \(lifetime.rawValue)"
    }
}

public enum WorkspaceAccessLeaseError:
    Error,
    Sendable,
    Hashable,
    LocalizedError
{
    case empty_id
    case turn_lifetime_requires_turn_id
    case invalid_duration(TimeInterval)
    case root_identifier_conflict(String)

    public var errorDescription: String? {
        switch self {
        case .empty_id:
            return "Workspace access lease identifier cannot be empty."

        case .turn_lifetime_requires_turn_id:
            return "Turn-scoped workspace access lease requires a source turn identifier."

        case .invalid_duration(let duration):
            return "Workspace access lease duration '\(duration)' must be finite and non-negative."

        case .root_identifier_conflict(let identifier):
            return "Workspace access lease root '\(identifier)' conflicts with an existing workspace root."
        }
    }
}
