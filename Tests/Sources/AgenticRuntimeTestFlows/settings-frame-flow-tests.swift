import AgenticConfiguration
import AgenticRuntime
import Foundation
import Path
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    /// `settings.frame`: the `settings` binding, named path scopes, and a
    /// mistake reported with its file, line and field.
    static func runSettingsFrame() async throws -> [TestDiagnostic] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-frame-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = AgentHome(root: root, kind: .ephemeral)

        try Expect.equal(try home.settings(), AgenticSettings(), "no file: defaults")

        try """
            import Agentic;

            let notes: PathScope = .{
                .path = "~/notes/**",
                .sessions = .all,
            };
            let manual: PathScope = .{ .path = "/tmp/manual.pdf", .readOnly = true };

            var settings: AgenticSettings = .{
                .paths = .{ .ask = [notes], .symlinks = .never },
                .mutations = .{ .publication = .review },
            };
            settings.log = .{ .durability = .buffered };
            settings.exports = .{ .directory = "~/exports" };
            """.write(to: home.layout.settingsfile, atomically: true, encoding: .utf8)

        let settings = try home.settings()
        try Expect.equal(settings.mutations.publication, .review, "members decode as enum cases")
        try Expect.equal(settings.log.durability, .buffered, "a var field reassigned later")
        try Expect.equal(settings.paths.ask.map(\.path), ["~/notes/**"], "a scope referenced by name")
        try Expect.equal(settings.paths.symlinks, .never, "symlink policy")
        try Expect.equal(AgenticSettings().paths.symlinks, .roots, "symlinks default to roots")
        try Expect.equal(
            settings.exports.resolvedDirectory(workspace: "/work").path,
            NSHomeDirectory() + "/exports",
            "~ in the exports directory is the home"
        )
        try Expect.equal(
            AgenticSettings().exports.resolvedDirectory(workspace: "/work").path,
            "/work/.agentic/artifacts/exports",
            "exports default under the workspace's .agentic/artifacts"
        )
        let scopes = try home.pathScopes()
        try Expect.equal(Set(scopes.keys), ["notes", "manual"], "every PathScope binding")
        try Expect.equal(
            try scopes["notes"]?.resolvedPath(),
            NSHomeDirectory() + "/notes",
            "dir/** names the directory, ~ the home"
        )
        try Expect.equal(scopes["manual"]?.readOnly, true, "read-only scope")

        try """
            import Agentic;
            let settings: AgenticSettings = .{
                .mutations = .{ .publicaton = .review },
            };
            """.write(to: home.layout.settingsfile, atomically: true, encoding: .utf8)
        do {
            _ = try home.settings()
            throw SettingsFrameFixtureError.accepted
        } catch let error as AgenticSettingsError {
            let message = error.localizedDescription
            try Expect.true(
                message.contains("settings.frame") && message.contains("2:") && message.contains("publicaton"),
                "a typo names the file, line and field: \(message)"
            )
        }
        return []
    }
}

extension AgenticProgramRuntimeFlowTesting {
    /// A new home gets the template, which declares the current schema; a
    /// file's declared schema is compared with the program's; modernizing
    /// archives the file and writes the template.
    static func runSettingsTemplate() async throws -> [TestDiagnostic] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-template-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = AgentHome(root: root, kind: .ephemeral)
        let file = home.layout.settingsfile
        let current = AgenticSettings.schemaVersion

        try Expect.equal(try home.settingsSchemaStanding(), .missing, "no file")
        try home.prepareSettingsFile()
        try Expect.equal(try home.settingsSchemaStanding(), .current, "the template declares the current schema")
        try Expect.equal(try home.settings().schema, current, "and decodes to it")
        var expected = AgenticSettings()
        expected.schema = current
        try Expect.equal(try home.settings(), expected, "every other setting at its default")

        func declaring(_ major: Int, _ minor: Int, _ patch: Int) -> String {
            """
            import Agentic;
            let settings: AgenticSettings = .{
                .schema = .{ .major = \(major), .minor = \(minor), .patch = \(patch) },
            };
            """
        }
        let handwritten = "import Agentic;\nlet settings: AgenticSettings = .{};\n"
        try handwritten.write(to: file, atomically: true, encoding: .utf8)
        try home.prepareSettingsFile()
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), handwritten, "an existing file is never changed at start")
        try Expect.equal(try home.settingsSchemaStanding(), .undeclared, "no .schema")

        try declaring(current.major, current.minor + 1, 0).write(to: file, atomically: true, encoding: .utf8)
        try Expect.equal(
            try home.settingsSchemaStanding(),
            .newer(.init(major: current.major, minor: current.minor + 1, patch: 0)),
            "written for a newer program"
        )
        try declaring(current.major - 1, 4, 0).write(to: file, atomically: true, encoding: .utf8)
        try Expect.equal(
            try home.settingsSchemaStanding(),
            .incompatible(.init(major: current.major - 1, minor: 4, patch: 0)),
            "an older major version"
        )

        try handwritten.write(to: file, atomically: true, encoding: .utf8)
        let kept = try home.modernizeSettingsFile(now: Date(timeIntervalSince1970: 1_763_400_000))
        try Expect.equal(kept?.deletingLastPathComponent().path, home.layout.archivedir.path, "archived in the home")
        try Expect.equal(try kept.map { try String(contentsOf: $0, encoding: .utf8) }, handwritten, "the old file kept whole")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), AgenticSettingsTemplate.text, "and the template written")
        let made = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        try Expect.true(!made.contains { $0.contains("safe-file-backups") || $0.contains(".bak") }, "no Writers backups: \(made)")
        return []
    }
}

private enum SettingsFrameFixtureError: Error {
    case accepted
}
