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
    /// A new home gets the template; an untouched older template is
    /// archived and regenerated; an edited file is only replaced on request.
    static func runSettingsTemplate() async throws -> [TestDiagnostic] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-template-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = AgentHome(root: root, kind: .ephemeral)
        let file = home.layout.settingsfile
        let now = Date(timeIntervalSince1970: 1_763_400_000)

        try Expect.equal(try home.prepareSettingsFile(now: now), .written, "a new home gets the template")
        try Expect.equal(try home.settings(), AgenticSettings(), "the template decodes to the defaults")
        try Expect.equal(try home.prepareSettingsFile(now: now), .current, "then is left as it is")

        let oldBody = "import Agentic;\n"
        try (AgenticSettingsTemplate.marker(revision: 0, digest: AgenticSettingsTemplate.digest(oldBody)) + "\n" + oldBody)
            .write(to: file, atomically: true, encoding: .utf8)
        guard case .modernized(let archive) = try home.prepareSettingsFile(now: now) else {
            throw SettingsFrameFixtureError.accepted
        }
        try Expect.equal(archive.deletingLastPathComponent().path, home.layout.archivedir.path, "archived in the home")
        try Expect.true(try String(contentsOf: archive, encoding: .utf8).hasSuffix(oldBody), "the old file kept whole")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), AgenticSettingsTemplate.text, "regenerated")

        let edited = AgenticSettingsTemplate.text + "let extra: PathScope = .{ .path = \"/tmp\" };\n"
        try edited.write(to: file, atomically: true, encoding: .utf8)
        try Expect.equal(try home.prepareSettingsFile(now: now), .edited, "an edited current file stays")
        let handwritten = "import Agentic;\nlet settings: AgenticSettings = .{};\n"
        try handwritten.write(to: file, atomically: true, encoding: .utf8)
        try Expect.equal(try home.prepareSettingsFile(now: now), .outdated(revision: nil), "an unmarked file stays")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), handwritten, "untouched")

        let later = now.addingTimeInterval(1)
        let kept = try home.modernizeSettingsFile(now: later)
        try Expect.equal(try kept.map { try String(contentsOf: $0, encoding: .utf8) }, handwritten, "modernizing on request archives it")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), AgenticSettingsTemplate.text, "and writes the template")
        return []
    }
}

private enum SettingsFrameFixtureError: Error {
    case accepted
}
