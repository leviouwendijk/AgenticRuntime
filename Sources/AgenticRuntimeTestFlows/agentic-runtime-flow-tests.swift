import Agentic
import AgenticInterfaces
import AgenticRuntime
import AgenticExecution
import AgenticIO
import Foundation
import TestFlows

private struct RuntimeFixtureApplication:
    AgenticApplicationProviding
{
    static let application = Agentic.application(
        "runtime-fixture",
        title: "Runtime Fixture",
        metadata: [
            "fixture": "true",
        ]
    ) {
        tools {
            CoreFileToolSet()
        }

        skills {
            AgentSkill(
                identifier: "runtime-fixture-skill",
                name: "Runtime Fixture Skill",
                summary: "Proves runtime skill realization.",
                body: "Runtime realizes application declarations without selecting concrete domain packages."
            )
        }
    }
}

enum AgenticRuntimeFlowTesting {
    static func runApplicationRealization()
        async throws -> [TestFlowDiagnostic]
    {
        let runtime = try await AgenticRuntime.resolve(
            RuntimeFixtureApplication.self
        )

        try Expect.equal(
            runtime.application.identifier.rawValue,
            "runtime-fixture",
            "runtime application identifier"
        )

        try Expect.equal(
            runtime.tools.count,
            4,
            "runtime realized CoreFileToolSet"
        )

        try Expect.equal(
            runtime.skills.count,
            1,
            "runtime realized application skills"
        )

        return [
            .field(
                "application",
                runtime.application.identifier.rawValue
            ),
            .field(
                "tools",
                String(runtime.tools.count)
            ),
            .field(
                "skills",
                String(runtime.skills.count)
            ),
        ]
    }

    static func runHostParity()
        async throws -> [TestFlowDiagnostic]
    {
        let runtime = try await AgenticRuntime.resolve(
            RuntimeFixtureApplication.self
        )

        let workspaceRoot = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "agentic-runtime-host-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: workspaceRoot,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: workspaceRoot
            )
        }

        let host = try runtime.host(
            workspacePath: workspaceRoot.path,
            sessionID: "runtime-host-session"
        )

        let list = host.list()
        let manifest = try host.capabilityManifestText()

        try Expect.equal(
            list.action,
            .list,
            "host list action"
        )

        try Expect.contains(
            manifest,
            "runtime-host-session",
            "manifest session"
        )

        try Expect.contains(
            manifest,
            workspaceRoot.path,
            "manifest workspace"
        )

        try Expect.contains(
            manifest,
            "read_file",
            "manifest runtime tools"
        )

        return [
            .field(
                "workspace",
                workspaceRoot.path
            ),
            .field(
                "session",
                "runtime-host-session"
            ),
            .field(
                "tool_count",
                String(runtime.tools.count)
            ),
        ]
    }
}
