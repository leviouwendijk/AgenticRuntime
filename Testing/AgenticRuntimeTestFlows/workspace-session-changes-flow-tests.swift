import AgenticIO
import IO
import AgenticRuntime
import Workspace
import Foundation
import Path
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    /// Operator changes on top of a base Workspace: a leased outer root,
    /// a restriction, the working directory, and revoking each.
    static func runWorkspaceSessionChanges()
        async throws
        -> [TestDiagnostic]
    {
        let fixture = URL(
            fileURLWithPath: "/agentic-session-workspace-fixture",
            isDirectory: true
        )
        let project = fixture.appendingPathComponent(
            "project",
            isDirectory: true
        )
        let projectID = PathAccessRootIdentifier(
            rawValue: "project"
        )
        let base = try Workspace(
            root: PathAccessRoot(
                id: projectID,
                label: "Project",
                scope: try PathAccessScope(
                    root: project
                ),
                isDefault: true
            ),
            grants: [
                try WorkspaceGrant(
                    id: WorkspaceGrantIdentifier(
                        "project-all"
                    ),
                    rootIdentifier: projectID,
                    capabilities: Set(
                        WorkspaceCapability.allCases
                    )
                ),
            ]
        )
        let outer = try WorkspaceAccessLease(
            id: "outer-lease",
            request: WorkspaceAccessRequest(
                rootID: "fixture",
                rootPath: fixture.path,
                label: "fixture",
                capabilities: [
                    .list,
                    .read,
                ],
                reason: "operator :path add",
                policyProfile: "workspace",
                durationSeconds: nil
            ),
            lifetime: .session,
            origin: .operator_command
        )
        var leases = try WorkspaceAccessLeases().activating(
            outer,
            baseWorkspace: base,
            turnID: nil
        )

        func effective() throws -> Workspace {
            guard let workspace = try leases.effectiveWorkspace(
                base: base,
                turnID: nil
            ) else {
                throw WorkspaceSessionChangesFixtureError.workspace_missing
            }
            return workspace
        }

        let fixtureID = PathAccessRootIdentifier(
            rawValue: "fixture"
        )
        try Expect.equal(
            try effective().authorize(
                "other/notes.txt",
                rootIdentifier: fixtureID,
                capability: .read
            ).authorizedPath.rootIdentifier,
            fixtureID,
            "the leased outer root reads outside the base root"
        )
        try Expect.true(
            (try? effective().authorize(
                "other/notes.txt",
                rootIdentifier: fixtureID,
                capability: .write
            )) == nil,
            "the leased root grants only its own capabilities"
        )
        try Expect.equal(
            try effective().authorize(
                "project/Sources/a.swift",
                rootIdentifier: fixtureID,
                capability: .write
            ).authorizedPath.rootIdentifier,
            projectID,
            "the base root still governs its subtree under the outer lease"
        )

        leases = try leases.restricting(
            WorkspaceAccessRestriction(
                id: "deny-secret",
                rootID: projectID.rawValue,
                pattern: "secret.txt",
                rule: .denyBasename(
                    "secret.txt"
                )
            ),
            baseWorkspace: base,
            turnID: nil
        )
        try Expect.true(
            (try? effective().authorize(
                "secret.txt",
                capability: .read
            )) == nil,
            "a restriction denies on the base root"
        )

        leases = try leases.changingDirectory(
            to: project.appendingPathComponent("Sources").path,
            baseWorkspace: base,
            turnID: nil
        )
        let sources = try leases.context(
            in: effective(),
            execution: .init(
                io: .blocking,
                mutations: .immediate
            )
        )
        try Expect.equal(
            try sources.authorize(
                "a.swift",
                capability: .read
            ).authorizedPath.presentationPath,
            "Sources/a.swift",
            "relative paths resolve against the working directory"
        )

        var outsideRefused = false
        do {
            _ = try leases.changingDirectory(
                to: "/elsewhere",
                baseWorkspace: base,
                turnID: nil
            )
        } catch WorkspaceAccessLeasesError.directory_outside_workspace {
            outsideRefused = true
        }
        try Expect.true(
            outsideRefused,
            "changing directory never adds a root"
        )

        leases = try leases.changingDirectory(
            to: fixture.appendingPathComponent("other").path,
            baseWorkspace: base,
            turnID: nil
        )
        try Expect.equal(
            try effective().defaultRootIdentifier,
            fixtureID,
            "a directory in the leased root makes that root the default"
        )

        leases = try leases.revoking(
            "outer-lease"
        )
        try Expect.true(
            leases.directory == nil && leases.values.isEmpty,
            "revoking a lease also leaves a working directory under it"
        )
        try Expect.equal(
            try effective().rootIdentifiers,
            [projectID],
            "the revoked root is gone"
        )
        try Expect.equal(
            leases.restrictions.map(\.id),
            ["deny-secret"],
            "restrictions on other roots stay"
        )

        leases = try leases.revoking(
            "deny-secret"
        )
        try Expect.true(
            (try? effective().authorize(
                "secret.txt",
                capability: .read
            )) != nil,
            "revoking the restriction restores access"
        )

        var unknownRefused = false
        do {
            _ = try leases.revoking(
                "nothing"
            )
        } catch WorkspaceAccessLeasesError.lease_not_found {
            unknownRefused = true
        }
        try Expect.true(
            unknownRefused,
            "revoking an unknown id is an error"
        )

        return []
    }
}

private enum WorkspaceSessionChangesFixtureError: Error {
    case workspace_missing
}
