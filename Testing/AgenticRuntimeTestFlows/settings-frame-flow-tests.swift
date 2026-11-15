import AgenticRuntime
import Foundation
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
            import agentic;

            let notes: PathScope = .{
                .path = "~/notes/**",
                .sessions = .all,
            };
            let manual: PathScope = .{ .path = "/tmp/manual.pdf", .readOnly = true };

            var settings: AgenticSettings = .{
                .paths = .{ .ask = [notes] },
                .mutations = .{ .publication = .review },
            };
            settings.log = .{ .durability = .buffered };
            """.write(to: home.layout.settingsfile, atomically: true, encoding: .utf8)

        let settings = try home.settings()
        try Expect.equal(settings.mutations.publication, .review, "members decode as enum cases")
        try Expect.equal(settings.log.durability, .buffered, "a var field reassigned later")
        try Expect.equal(settings.paths.ask.map(\.path), ["~/notes/**"], "a scope referenced by name")
        let scopes = try home.pathScopes()
        try Expect.equal(Set(scopes.keys), ["notes", "manual"], "every PathScope binding")
        try Expect.equal(
            try scopes["notes"]?.resolvedPath(),
            NSHomeDirectory() + "/notes",
            "dir/** names the directory, ~ the home"
        )
        try Expect.equal(scopes["manual"]?.readOnly, true, "read-only scope")

        try """
            import agentic;
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

private enum SettingsFrameFixtureError: Error {
    case accepted
}
