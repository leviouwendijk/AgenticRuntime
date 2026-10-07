import AgenticIO
import AgenticRuntime
import Workspace
import Foundation
import Path
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runWorkspaceAccessLeaseActivation()
        async throws
        -> [TestDiagnostic]
    {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-runtime-workspace-access-\(UUID().uuidString)",
                isDirectory: true
            )
        let projectRoot = fixtureRoot.appendingPathComponent(
            "project",
            isDirectory: true
        )
        let turnRoot = fixtureRoot.appendingPathComponent(
            "turn",
            isDirectory: true
        )
        let sessionRoot = fixtureRoot.appendingPathComponent(
            "session",
            isDirectory: true
        )
        let turnFile = turnRoot.appendingPathComponent(
            "turn.txt",
            isDirectory: false
        )

        try FileManager.default.createDirectory(
            at: projectRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: turnRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sessionRoot,
            withIntermediateDirectories: true
        )
        try "turn fixture\n".write(
            to: turnFile,
            atomically: true,
            encoding: .utf8
        )

        defer {
            try? FileManager.default.removeItem(
                at: fixtureRoot
            )
        }

        let projectRootID = PathAccessRootIdentifier(
            rawValue: "project"
        )
        let baseWorkspace = try Workspace(
            root: PathAccessRoot(
                id: projectRootID,
                label: "Project",
                scope: try PathAccessScope(
                    root: projectRoot,
                    policy: .defaults.workspace
                ),
                isDefault: true
            ),
            grants: [
                try WorkspaceGrant(
                    id: WorkspaceGrantIdentifier(
                        "fixture-project-grant"
                    ),
                    rootIdentifier: projectRootID,
                    capabilities: Set(
                        WorkspaceCapability.allCases
                    )
                ),
            ]
        )
        let currentTurnID = "fixture-turn-current"
        let otherTurnID = "fixture-turn-other"
        let activatedAt = Date(
            timeIntervalSince1970: 1_800_000_000
        )
        let turnRootID = PathAccessRootIdentifier(
            rawValue: "fixture_turn"
        )
        let turnRequest = WorkspaceAccessRequest(
            rootID: turnRootID.rawValue,
            rootPath: turnRoot.path,
            label: "Fixture Turn",
            capabilities: [
                .list,
                .read,
            ],
            reason: "Exercise turn-scoped Runtime workspace access.",
            policyProfile: "workspace",
            durationSeconds: 60
        )
        let turnLease = try WorkspaceAccessLease(
            request: turnRequest,
            lifetime: .turn,
            activatedAt: activatedAt,
            sourceTurnID: currentTurnID
        )
        var leases = try WorkspaceAccessLeases()
            .activating(
                turnLease,
                baseWorkspace: baseWorkspace,
                turnID: currentTurnID,
                at: activatedAt
            )

        try Expect.equal(
            turnLease.expiresAt,
            activatedAt.addingTimeInterval(60),
            "wall-clock duration starts when workspace authority is granted"
        )

        guard let turnEffective = try leases.effectiveWorkspace(
            base: baseWorkspace,
            turnID: currentTurnID,
            at: activatedAt
        ),
              let otherTurnBeforeSession = try leases.effectiveWorkspace(
                base: baseWorkspace,
                turnID: otherTurnID,
                at: activatedAt
              )
        else {
            throw WorkspaceAccessLeaseActivationFixtureError
                .workspace_missing
        }

        let authorizedTurnFile = try turnEffective.authorize(
            "turn.txt",
            rootIdentifier: turnRootID,
            capability: .read
        )

        try Expect.equal(
            baseWorkspace.rootIdentifiers.count,
            1,
            "base workspace remains unchanged after temporary grant activation"
        )
        try Expect.equal(
            turnEffective.rootIdentifiers.count,
            2,
            "activating turn sees base workspace plus its turn authority"
        )
        try Expect.equal(
            otherTurnBeforeSession.rootIdentifiers.count,
            1,
            "another turn does not inherit turn-scoped authority"
        )
        try Expect.equal(
            authorizedTurnFile.authorizedPath.absoluteURL
                .standardizedFileURL.path,
            turnFile.standardizedFileURL.path,
            "turn-scoped effective workspace authorizes the exact approved external path"
        )

        let sessionRootID = PathAccessRootIdentifier(
            rawValue: "fixture_session"
        )
        let sessionRequest = WorkspaceAccessRequest(
            rootID: sessionRootID.rawValue,
            rootPath: sessionRoot.path,
            label: "Fixture Session",
            capabilities: [
                .list,
                .read,
            ],
            reason: "Exercise session-scoped Runtime workspace access.",
            policyProfile: "workspace",
            durationSeconds: nil
        )
        let sessionLease = try WorkspaceAccessLease(
            request: sessionRequest,
            lifetime: .session,
            sourceTurnID: currentTurnID
        )

        leases = try leases.activating(
            sessionLease,
            baseWorkspace: baseWorkspace,
            turnID: currentTurnID,
            at: activatedAt
        )

        guard let currentWithSession = try leases.effectiveWorkspace(
            base: baseWorkspace,
            turnID: currentTurnID,
            at: activatedAt
        ),
              let otherWithSession = try leases.effectiveWorkspace(
                base: baseWorkspace,
                turnID: otherTurnID,
                at: activatedAt
              )
        else {
            throw WorkspaceAccessLeaseActivationFixtureError
                .workspace_missing
        }

        try Expect.equal(
            currentWithSession.rootIdentifiers.count,
            3,
            "current turn composes base, turn, and session authority"
        )
        try Expect.equal(
            otherWithSession.rootIdentifiers.count,
            2,
            "other turns inherit session authority but not another turn's authority"
        )
        try Expect.equal(
            otherWithSession.rootIdentifiers.contains(
                sessionRootID
            ),
            true,
            "session-scoped root is visible to another turn"
        )
        try Expect.equal(
            otherWithSession.rootIdentifiers.contains(
                turnRootID
            ),
            false,
            "turn-scoped root remains isolated from another turn"
        )

        let encodedLeases = try JSONEncoder().encode(
            leases
        )
        let decodedLeases = try JSONDecoder().decode(
            WorkspaceAccessLeases.self,
            from: encodedLeases
        )

        try Expect.equal(
            decodedLeases,
            leases,
            "workspace-access leases survive durable encode/decode"
        )

        let suspension = Run.Suspension.workspace_access(
            turnRequest,
            metadata: [
                "toolCallID": "fixture-request",
                "toolName": "request_path_grant"
            ]
        )
        let interaction = Run.Interaction.Request(
            sessionID: currentTurnID,
            suspension: suspension
        )
        let response = Run.Interaction.Response(
            request: interaction,
            resolution: .workspace_access(
                .grant_for_turn
            )
        )
        let encodedResponse = try JSONEncoder().encode(
            response
        )
        let decodedResponse = try JSONDecoder().decode(
            Run.Interaction.Response.self,
            from: encodedResponse
        )

        try Expect.equal(
            interaction.kind,
            .workspace_access,
            "workspace-access suspension projects a first-class interaction kind"
        )
        try Expect.equal(
            decodedResponse,
            response,
            "workspace-access interaction resolution survives durable encode/decode"
        )
        try Expect.equal(
            WorkspaceAccessResolution.grant_for_turn.lifetime,
            .turn,
            "turn grant resolution projects turn-scoped lease lifetime"
        )
        try Expect.equal(
            WorkspaceAccessResolution.grant_for_session.lifetime,
            .session,
            "session grant resolution projects session-scoped lease lifetime"
        )
        try Expect.equal(
            WorkspaceAccessResolution.deny.lifetime,
            nil,
            "denial installs no workspace authority lifetime"
        )

        let afterTurn = leases.endingTurn(
            currentTurnID
        )
        guard let afterTurnWorkspace = try afterTurn.effectiveWorkspace(
            base: baseWorkspace,
            turnID: currentTurnID,
            at: activatedAt
        ) else {
            throw WorkspaceAccessLeaseActivationFixtureError
                .workspace_missing
        }

        try Expect.equal(
            afterTurnWorkspace.rootIdentifiers.count,
            2,
            "ending a turn removes turn-scoped authority while preserving session authority"
        )
        try Expect.equal(
            afterTurnWorkspace.rootIdentifiers.contains(
                turnRootID
            ),
            false,
            "ended turn no longer has its temporary turn root"
        )
        try Expect.equal(
            afterTurnWorkspace.rootIdentifiers.contains(
                sessionRootID
            ),
            true,
            "session authority survives turn completion"
        )

        return [
            .field(
                "base_roots",
                String(
                    baseWorkspace.rootIdentifiers.count
                )
            ),
            .field(
                "current_turn_roots",
                String(
                    currentWithSession.rootIdentifiers.count
                )
            ),
            .field(
                "other_turn_roots",
                String(
                    otherWithSession.rootIdentifiers.count
                )
            ),
            .field(
                "after_turn_roots",
                String(
                    afterTurnWorkspace.rootIdentifiers.count
                )
            ),
            .field(
                "interaction_kind",
                interaction.kind.rawValue
            ),
        ]
    }
}

private enum WorkspaceAccessLeaseActivationFixtureError: Error {
    case workspace_missing
}
