import Agentic
import AgenticInterfaces
import AgenticRuntime
import AgenticExecution
import AgenticWorkspace
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

    static func runWorkspaceResourceResolution()
        async throws -> [TestFlowDiagnostic]
    {
        let workspaceRoot = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "agentic-resource-resolution-\(UUID().uuidString)",
                isDirectory: true
            )
        let fixtureURL = workspaceRoot.appendingPathComponent(
            "fixture.bin",
            isDirectory: false
        )
        let fixtureData = Data(
            "resource-fixture".utf8
        )

        try FileManager.default.createDirectory(
            at: workspaceRoot,
            withIntermediateDirectories: true
        )
        try fixtureData.write(
            to: fixtureURL,
            options: .atomic
        )

        defer {
            try? FileManager.default.removeItem(
                at: workspaceRoot
            )
        }

        let workspace = try AgentWorkspace(
            root: workspaceRoot
        )
        let resolver = WorkspaceAgentResourceResolver(
            workspace: workspace
        )

        let reference = try await resolver.resolve(
            AgentResource(
                id: "reference-fixture",
                modality: .document,
                source: .init(
                    kind: .reference,
                    value: "fixture.bin"
                ),
                contentType: "application/octet-stream"
            )
        )

        let uri = try await resolver.resolve(
            AgentResource(
                id: "uri-fixture",
                modality: .document,
                source: .init(
                    kind: .uri,
                    value: fixtureURL.absoluteString
                ),
                contentType: "application/octet-stream"
            )
        )

        try Expect.equal(
            reference.data,
            fixtureData,
            "workspace reference resource data"
        )

        try Expect.equal(
            reference.byteCount,
            fixtureData.count,
            "workspace reference resource byte count"
        )

        try Expect.equal(
            reference.resource.metadata.filename ?? "",
            "fixture.bin",
            "workspace reference resource filename"
        )

        try Expect.equal(
            uri.data,
            fixtureData,
            "workspace file URI resource data"
        )

        return [
            .field(
                "reference_bytes",
                String(reference.byteCount)
            ),
            .field(
                "uri_bytes",
                String(uri.byteCount)
            ),
        ]
    }
}
