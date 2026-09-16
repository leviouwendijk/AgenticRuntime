import AgenticRuntime
import AgenticWorkspace
import Foundation
import Path
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runWorkspaceAccessLeaseActivation()
        async throws
        -> [TestFlowDiagnostic]
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

        let baseWorkspace = try AgentWorkspace(
            root: projectRoot
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
            overlay: try fixtureWorkspaceAccessOverlay(
                rootID: turnRootID,
                label: "Fixture Turn",
                rootURL: turnRoot,
                grantID: "fixture-turn-grant"
            ),
            durationSeconds: 60
        )
        let turnLease = try AgentWorkspaceAccessLease(
            overlay: turnRequest.overlay,
            lifetime: .turn,
            durationSeconds: turnRequest.durationSeconds,
            activatedAt: activatedAt,
            sourceTurnID: currentTurnID
        )
        var leases = try AgentWorkspaceAccessLeases()
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

        let authorizedTurnFile = try turnEffective
            .accessController
            .authorize(
                rootID: turnRootID,
                path: "turn.txt",
                capability: .read,
                toolName: "read_file",
                type: .file
            )

        try Expect.equal(
            baseWorkspace.accessController.rootIdentifiers.count,
            1,
            "base workspace remains unchanged after temporary grant activation"
        )
        try Expect.equal(
            turnEffective.accessController.rootIdentifiers.count,
            2,
            "activating turn sees base workspace plus its turn overlay"
        )
        try Expect.equal(
            otherTurnBeforeSession.accessController.rootIdentifiers.count,
            1,
            "another turn does not inherit turn-scoped authority"
        )
        try Expect.equal(
            authorizedTurnFile.absoluteURL.standardizedFileURL.path,
            turnFile.standardizedFileURL.path,
            "turn-scoped effective workspace authorizes the exact approved external path"
        )

        let sessionRootID = PathAccessRootIdentifier(
            rawValue: "fixture_session"
        )
        let sessionRequest = WorkspaceAccessRequest(
            overlay: try fixtureWorkspaceAccessOverlay(
                rootID: sessionRootID,
                label: "Fixture Session",
                rootURL: sessionRoot,
                grantID: "fixture-session-grant"
            )
        )
        let sessionLease = try AgentWorkspaceAccessLease(
            overlay: sessionRequest.overlay,
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
            currentWithSession.accessController.rootIdentifiers.count,
            3,
            "current turn composes base, turn, and session authority"
        )
        try Expect.equal(
            otherWithSession.accessController.rootIdentifiers.count,
            2,
            "other turns inherit session authority but not another turn's authority"
        )
        try Expect.equal(
            otherWithSession.accessController.rootIdentifiers.contains(
                sessionRootID
            ),
            true,
            "session-scoped root is visible to another turn"
        )
        try Expect.equal(
            otherWithSession.accessController.rootIdentifiers.contains(
                turnRootID
            ),
            false,
            "turn-scoped root remains isolated from another turn"
        )

        let encodedLeases = try JSONEncoder().encode(
            leases
        )
        let decodedLeases = try JSONDecoder().decode(
            AgentWorkspaceAccessLeases.self,
            from: encodedLeases
        )

        try Expect.equal(
            decodedLeases,
            leases,
            "workspace-access leases survive durable encode/decode"
        )

        let suspension = AgentSuspension.workspace_access(
            turnRequest,
            metadata: [
                "toolCallID": "fixture-request",
                "toolName": "request_path_grant"
            ]
        )
        let interaction = AgentInteraction.Request(
            sessionID: currentTurnID,
            suspension: suspension
        )
        let response = AgentInteraction.Response(
            request: interaction,
            resolution: .workspace_access(
                .grant_for_turn
            )
        )
        let encodedResponse = try JSONEncoder().encode(
            response
        )
        let decodedResponse = try JSONDecoder().decode(
            AgentInteraction.Response.self,
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

        let afterTurn = leases
            .endingTurn(
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
            afterTurnWorkspace.accessController.rootIdentifiers.count,
            2,
            "ending a turn removes turn-scoped authority while preserving session authority"
        )
        try Expect.equal(
            afterTurnWorkspace.accessController.rootIdentifiers.contains(
                turnRootID
            ),
            false,
            "ended turn no longer has its temporary turn root"
        )
        try Expect.equal(
            afterTurnWorkspace.accessController.rootIdentifiers.contains(
                sessionRootID
            ),
            true,
            "session authority survives turn completion"
        )

        return [
            .field(
                "base_roots",
                String(
                    baseWorkspace.accessController.rootIdentifiers.count
                )
            ),
            .field(
                "current_turn_roots",
                String(
                    currentWithSession.accessController.rootIdentifiers.count
                )
            ),
            .field(
                "other_turn_roots",
                String(
                    otherWithSession.accessController.rootIdentifiers.count
                )
            ),
            .field(
                "after_turn_roots",
                String(
                    afterTurnWorkspace.accessController.rootIdentifiers.count
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

private func fixtureWorkspaceAccessOverlay(
    rootID: PathAccessRootIdentifier,
    label: String,
    rootURL: URL,
    grantID: String
) throws -> WorkspaceAccessOverlay {
    try WorkspaceAccessOverlay(
        roots: [
            .init(
                root: .init(
                    id: rootID,
                    label: label,
                    scope: try PathAccessScope(
                        root: rootURL,
                        policy: .defaults.workspace
                    ),
                    details: "Runtime workspace-access lease fixture.",
                    isDefault: false
                ),
                grant: .init(
                    id: grantID,
                    rootID: rootID,
                    mode: .read_only,
                    capabilities: [
                        .list,
                        .read,
                    ],
                    allowedTools: [
                        "read_file",
                    ],
                    reason: "Exercise scoped Runtime workspace-access lease activation."
                )
            ),
        ]
    )
}
