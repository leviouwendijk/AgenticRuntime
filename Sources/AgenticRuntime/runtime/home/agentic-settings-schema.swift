import Foundation
import Frame
import Path

/// What editors offer inside `settings.frame`; `AgenticFrame.install()`
/// writes it where they find it. The decoders above still decide what holds.
extension AgenticSettings: FrameDescribable {
    public static var frameSchema: Frame.Schema {
        .object([
            .init("schema", .object([
                .init("major", .integer, required: true),
                .init("minor", .integer, required: true),
                .init("patch", .integer, required: true),
            ]), summary: "The settings schema this file is written for; the template declares the current one."),
            .init("exports", .of(Exports.self)),
            .init("log", .of(Log.self)),
            .init("mutations", .of(Mutations.self)),
            .init("paths", .of(Paths.self)),
        ], summary: "User settings of an Agentic home. Every field is optional and falls back to its default.")
    }
}

extension AgenticSettings.Paths: FrameDescribable {
    public static var frameSchema: Frame.Schema {
        let scopes = Frame.Schema.array(.of(PathScope.self))
        return .object([
            .init("allow", scopes, summary: "Reachable without asking."),
            .init("ask", scopes, summary: "Reachable once approved."),
            .init("deny", scopes, summary: "Never reachable."),
            .init("symlinks", .members(of: PathSymlinkPolicy.self, summaries: [
                .never: "No path through a symlink.",
                .roots: "A symlink is followed when it leads into one of the session's roots, and checked there. The default.",
                .anywhere: "Symlinks are not checked.",
            ]), summary: "Which symlinks a path may pass through."),
        ], summary: "Paths outside the workspace, by how they are treated. Applied at session start.")
    }
}

extension PathScope: FrameDescribable {
    public static var frameSchema: Frame.Schema {
        .object([
            .init("path", .string, required: true,
                  summary: "A path, a directory with everything below it (dir/**) or a single file; ~ is the home directory."),
            .init("sessions", .members(of: Sessions.self), summary: "Which sessions it is for; .all by default."),
            .init("readOnly", .boolean, summary: "Only list, read and scan."),
        ], summary: "A path and which sessions it is for.")
    }
}

extension AgenticSettings.Exports: FrameDescribable {
    public static var frameSchema: Frame.Schema {
        .object([
            .init("directory", .string,
                  summary: "Absolute, ~, or relative to the workspace; .agentic/artifacts/exports by default."),
        ], summary: "Where :export writes results.")
    }
}

extension AgenticSettings.Log: FrameDescribable {
    public static var frameSchema: Frame.Schema {
        .object([
            .init("durability", .members(of: Run.Log.Durability.self, summaries: [
                .buffered: "Staged in memory and written at step boundaries. A crash loses the unwritten tail.",
                .entry: "Written as appended; survives a crash or kill of the process. The default.",
                .synced: "Written and synchronized to stable storage; survives power loss. Slowest.",
            ]), summary: "How appended entries reach the disk."),
        ], summary: "How session logs are written.")
    }
}

extension AgenticSettings.Mutations: FrameDescribable {
    public static var frameSchema: Frame.Schema {
        .object([
            .init("publication", .members(of: Publication.self, summaries: [
                .approval: "The root agent's mutations publish once approved; workers follow .workers. The default.",
                .review: "Every mutation stays staged until the owner reviews and publishes it.",
            ])),
            .init("workers", .members(of: Workers.self, summaries: [
                .publish: "Written within the worker's scope once admitted; reviewed afterwards. The default.",
                .stage: "Staged off disk until the owner reviews and publishes it.",
            ]), summary: "What a delegated worker's admitted change does."),
        ], summary: "When coordinated file mutations reach the disk.")
    }
}

public extension AgenticFrame {
    /// Writes `Agentic.frame` where editors look for module files.
    @discardableResult
    static func install(into directory: URL = Frame.modulesDirectory) throws -> URL {
        try module.install(into: directory)
    }

    /// Writes `Agentic.frame` and every module the application's domains
    /// declare, such as `Scheduling.frame`.
    @discardableResult
    static func install<Application: AgenticApplicationProviding>(
        for application: Application.Type,
        into directory: URL = Frame.modulesDirectory
    ) throws -> [URL] {
        let declared = (application as? any AgenticFrameModulesProviding.Type)?.frameModules ?? []
        return try ([module] + declared).map { try $0.install(into: directory) }
    }
}

/// An application whose domains read their own `domains/<name>.frame`
/// files; their modules are installed with `Agentic.frame` for editors.
public protocol AgenticFrameModulesProviding: AgenticApplicationProviding {
    static var frameModules: [Frame.Module] { get }
    /// A complete file per domain to start from; `agentic example`
    /// prints them.
    static var frameExamples: [AgenticFrameExample] { get }
}

public extension AgenticFrameModulesProviding {
    static var frameExamples: [AgenticFrameExample] { [] }
}

/// A `.frame` file to start from, printed by `agentic example <name>`.
/// The text comes from the same source the program reads and tests, so it
/// cannot drift from what the program accepts.
public struct AgenticFrameExample: Sendable, Hashable {
    public let name: String
    /// Where it goes, relative to the home: `settings.frame`,
    /// `domains/scheduling.frame`.
    public let path: String
    public let summary: String
    public let text: String

    public init(name: String, path: String, summary: String, text: String) {
        self.name = name
        self.path = path
        self.summary = summary
        self.text = text
    }

    /// The home's `settings.frame`, as the first run writes it.
    public static var settings: Self {
        .init(
            name: "settings",
            path: "settings.frame",
            summary: "User settings: path scopes, mutations, logs, exports.",
            text: AgenticSettingsTemplate.text
        )
    }

    /// `settings` first, then what the application declares.
    public static func all<Application: AgenticApplicationProviding>(
        for application: Application.Type
    ) -> [Self] {
        let declared = (application as? any AgenticFrameModulesProviding.Type)?.frameExamples ?? []
        return [settings] + declared
    }
}
