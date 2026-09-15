import Agentic
import AgenticExecution
import AgenticIO
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
        let preparedIntentID = PreparedIntentIdentifier(
            rawValue: "fixture-path-grant-intent"
        )
        let activator = FixtureWorkspaceAccessActivator(
            baseWorkspace: baseWorkspace,
            currentTurnID: currentTurnID,
            activatedAt: activatedAt
        )
        let baseRegistry = try AgenticRuntimePreparedOperations.registry()
        let registry = try AgenticRuntimePreparedOperations.registry(
            workspaceAccessActivator: activator
        )

        try Expect.equal(
            baseRegistry.contains(
                PreparedPathGrantOperation.schema
            ),
            false,
            "Runtime does not install path-grant execution without an explicit workspace-access activator"
        )
        try Expect.equal(
            registry.contains(
                PreparedPathGrantOperation.schema
            ),
            true,
            "Runtime installs prepared path-grant execution only when a workspace-access activator is supplied"
        )

        let turnRootID = PathAccessRootIdentifier(
            rawValue: "fixture_turn"
        )
        let turnPlan = PreparedPathGrantOperation.Plan(
            overlay: try fixtureWorkspaceAccessOverlay(
                rootID: turnRootID,
                label: "Fixture Turn",
                rootURL: turnRoot,
                grantID: "fixture-turn-grant"
            ),
            lifetime: .turn,
            durationSeconds: 60
        )
        let turnResultEnvelope = try await registry.execute(
            try PreparedPathGrantOperation.envelope(
                turnPlan
            ),
            context: .init(
                sessionID: currentTurnID,
                preparedIntentID: preparedIntentID
            )
        )
        let turnResult = try PreparedPathGrantExecutor.result(
            from: turnResultEnvelope
        )

        try Expect.equal(
            turnResult.lease.overlay,
            turnPlan.overlay,
            "prepared path-grant execution delegates the exact approved workspace overlay without reconstruction"
        )
        try Expect.equal(
            turnResult.lease.lifetime,
            .turn,
            "prepared path-grant execution preserves exact requested lifetime"
        )
        try Expect.equal(
            turnResult.lease.sourceTurnID,
            currentTurnID,
            "turn-scoped activation binds the lease to the activating turn"
        )
        try Expect.equal(
            turnResult.lease.preparedIntentID,
            preparedIntentID,
            "workspace-access lease preserves prepared-intent provenance"
        )
        try Expect.equal(
            turnResult.lease.expiresAt,
            activatedAt.addingTimeInterval(60),
            "wall-clock duration starts at activation rather than request authoring"
        )

        guard let turnEffective = try await activator.effectiveWorkspace(
            turnID: currentTurnID,
            at: activatedAt
        ) else {
            throw WorkspaceAccessLeaseActivationFixtureError
                .workspace_missing
        }
        guard let otherTurnBeforeSession =
            try await activator.effectiveWorkspace(
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
        let sessionPlan = PreparedPathGrantOperation.Plan(
            overlay: try fixtureWorkspaceAccessOverlay(
                rootID: sessionRootID,
                label: "Fixture Session",
                rootURL: sessionRoot,
                grantID: "fixture-session-grant"
            ),
            lifetime: .session
        )
        let sessionResultEnvelope = try await registry.execute(
            try PreparedPathGrantOperation.envelope(
                sessionPlan
            ),
            context: .init(
                sessionID: currentTurnID,
                preparedIntentID: PreparedIntentIdentifier(
                    rawValue: "fixture-session-path-grant-intent"
                )
            )
        )
        let sessionResult = try PreparedPathGrantExecutor.result(
            from: sessionResultEnvelope
        )

        guard let currentWithSession =
            try await activator.effectiveWorkspace(
                turnID: currentTurnID,
                at: activatedAt
            ),
              let otherWithSession =
                try await activator.effectiveWorkspace(
                    turnID: otherTurnID,
                    at: activatedAt
                )
        else {
            throw WorkspaceAccessLeaseActivationFixtureError
                .workspace_missing
        }

        try Expect.equal(
            sessionResult.lease.lifetime,
            .session,
            "session-scoped prepared grant produces a session lease"
        )
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

        let encoded = try JSONEncoder().encode(
            await activator.snapshot()
        )
        let decoded = try JSONDecoder().decode(
            AgentWorkspaceAccessLeases.self,
            from: encoded
        )

        try Expect.equal(
            decoded,
            await activator.snapshot(),
            "workspace-access leases survive durable encode/decode"
        )

        await activator.endTurn(
            currentTurnID
        )

        guard let afterTurn =
            try await activator.effectiveWorkspace(
                turnID: currentTurnID,
                at: activatedAt
            )
        else {
            throw WorkspaceAccessLeaseActivationFixtureError
                .workspace_missing
        }

        try Expect.equal(
            afterTurn.accessController.rootIdentifiers.count,
            2,
            "ending a turn removes its turn-scoped authority while preserving session authority"
        )
        try Expect.equal(
            afterTurn.accessController.rootIdentifiers.contains(
                turnRootID
            ),
            false,
            "ended turn no longer has its temporary turn root"
        )
        try Expect.equal(
            afterTurn.accessController.rootIdentifiers.contains(
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
                    afterTurn.accessController.rootIdentifiers.count
                )
            ),
            .field(
                "prepared_operation",
                PreparedPathGrantOperation.schema.identifier.rawValue
            ),
        ]
    }
}

private actor FixtureWorkspaceAccessActivator:
    AgentWorkspaceAccessActivating
{
    let baseWorkspace: AgentWorkspace
    let currentTurnID: String
    let activatedAt: Date
    var leases = AgentWorkspaceAccessLeases()

    init(
        baseWorkspace: AgentWorkspace,
        currentTurnID: String,
        activatedAt: Date
    ) {
        self.baseWorkspace = baseWorkspace
        self.currentTurnID = currentTurnID
        self.activatedAt = activatedAt
    }

    func activate(
        _ plan: PreparedPathGrantOperation.Plan,
        context: PreparedOperation.Context
    ) async throws -> AgentWorkspaceAccessLease {
        let lease = try AgentWorkspaceAccessLease(
            overlay: plan.overlay,
            lifetime: plan.lifetime,
            durationSeconds: plan.durationSeconds,
            activatedAt: activatedAt,
            sourceTurnID: currentTurnID,
            preparedIntentID: context.preparedIntentID
        )

        leases = try leases.activating(
            lease,
            baseWorkspace: baseWorkspace,
            turnID: currentTurnID,
            at: activatedAt
        )

        return lease
    }

    func effectiveWorkspace(
        turnID: String,
        at date: Date
    ) throws -> AgentWorkspace? {
        try leases.effectiveWorkspace(
            base: baseWorkspace,
            turnID: turnID,
            at: date
        )
    }

    func snapshot() -> AgentWorkspaceAccessLeases {
        leases
    }

    func endTurn(
        _ turnID: String
    ) {
        leases = leases.endingTurn(
            turnID
        )
    }
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
                    isDefault: false
                ),
                grant: .init(
                    id: grantID,
                    rootID: rootID,
                    mode: .read_only,
                    capabilities: [
                        .list,
                        .scan,
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

private enum WorkspaceAccessLeaseActivationFixtureError:
    Error
{
    case workspace_missing
}
