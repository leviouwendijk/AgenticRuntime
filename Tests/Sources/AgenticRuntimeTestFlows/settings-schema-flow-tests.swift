import AgenticConfiguration
import AgenticRuntime
import Foundation
import Frame
import Path
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    /// The `Agentic` module file: its schema keeps up with the settings
    /// types, and an editor reading only the file sees what the program sees.
    static func runSettingsSchema() async throws -> [TestDiagnostic] {
        let everyField = AgenticSettings(
            schema: AgenticSettings.schemaVersion,
            exports: .init(directory: "~/exports"),
            log: .init(durability: .synced),
            mutations: .init(publication: .review, workers: .stage),
            paths: .init(
                allow: [.init(path: "~/notes/**", readOnly: true)],
                ask: [.init(path: "/tmp/a")],
                deny: [.init(path: "~/.ssh")],
                symlinks: .never
            )
        )
        try Expect.equal(
            try AgenticSettings.frameSchemaProblems(in: everyField).map(\.message),
            [],
            "the schema knows every field and case the settings encode"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentic-modules-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try FrameAgenticModule.install(into: directory)
        try Expect.equal(file.lastPathComponent, "Agentic.frame", "written by module name")
        let loaded = Frame.Environment.loading(modulesIn: directory)
        try Expect.equal(loaded.failures.count, 0, "the module file reads back")

        let settings = """
            import Agentic;

            let notes: PathScope = .{ .path = "~/notes/**", .sessions = .all };

            var settings: AgenticSettings = .{
                .paths = .{ .ask = [notes], .symlinks = .never },
                .mutations = .{ .publication = .review },
            };
            settings.log = .{ .durability = .buffered };
            """
        try Expect.equal(
            Frame.problems(in: try Frame.parse(settings), environment: loaded.environment).map(\.message),
            [],
            "valid settings pass the module file alone"
        )
        try Expect.equal(
            Frame.problems(in: try Frame.parse(settings), environment: FrameAgenticModule.environment).map(\.message),
            [],
            "and the program's own types"
        )

        let typo = """
            import Agentic;
            let settings: AgenticSettings = .{
                .mutations = .{ .publicaton = .review, .workers = .later },
            };
            """
        let problems = Frame.problems(in: try Frame.parse(typo), environment: loaded.environment)
            .map { $0.located(in: typo) }
        try Expect.equal(
            problems.map(\.message),
            [
                "'settings.mutations': unknown field 'publicaton'",
                "'settings.mutations.workers': unknown member '.later'; expected .publish, .stage",
            ],
            "every mistake, by field"
        )
        try Expect.equal(problems.compactMap(\.line), [3, 3], "on the line that holds it")
        return []
    }
}
