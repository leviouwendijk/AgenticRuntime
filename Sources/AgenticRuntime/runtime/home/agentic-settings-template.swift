import Foundation
import Frame
import IO
import Readers
import Version
import Writers

/// The `settings.frame` a home starts with: the schema it is written for,
/// and every setting commented out at its default, so the file decodes to
/// the defaults and shows what can be set. Keep it in step with
/// `AgenticSettings.schemaVersion`.
public enum AgenticSettingsTemplate {
    public static var text: String {
        let version = AgenticSettings.schemaVersion
        return """
            import Agentic;

            // A named path set: `:paths add notes` adds it to a conversation.
            // `dir/**` is the directory with everything below it; a plain path may
            // also be a single file. `.readOnly = true` limits it to list, read, scan.
            // let notes: PathScope = .{
            //     .path = "~/notes/**",
            //     .sessions = .all,
            //     .readOnly = false,
            // };

            // Agentic reads the `settings` binding; every field is optional and
            // falls back to the default shown.
            let settings: AgenticSettings = .{
                // The settings schema this file is written for. A newer minor
                // version only adds settings; a newer major one changes them.
                .schema = .{ .major = \(version.major), .minor = \(version.minor), .patch = \(version.patch) },

                // Paths outside the workspace, by how they are treated.
                // .paths = .{
                //     .allow = [],
                //     .ask = [notes],
                //     .deny = [],
                //     // .never, .roots (followed into a session root), .anywhere
                //     .symlinks = .roots,
                // },

                // When coordinated file mutations reach the disk.
                // .mutations = .{
                //     // .approval: publish once approved; .review: stage everything
                //     .publication = .approval,
                //     // .publish: written in scope, reviewed after; .stage: off disk
                //     .workers = .publish,
                // },

                // How session logs are written: .buffered, .entry, .synced.
                // .log = .{ .durability = .entry },

                // Where `:export` writes results: absolute, ~, or relative to the
                // workspace.
                // .exports = .{ .directory = ".agentic/artifacts/exports" },
            };

            """
    }
}

public extension AgenticSettings {
    /// A file's declared schema against the one this program reads.
    enum SchemaStanding: Sendable, Hashable {
        case missing
        case current
        /// No `.schema`: read as the current schema.
        case undeclared
        /// Same major version, older: read as it is; newer settings exist.
        case older(SemanticVersion)
        /// An older major version: fields may have changed meaning.
        case incompatible(SemanticVersion)
        /// Written for a newer program than this one.
        case newer(SemanticVersion)

        public init(declared: SemanticVersion?) {
            let current = AgenticSettings.schemaVersion
            guard let declared else {
                self = .undeclared
                return
            }
            if declared == current {
                self = .current
            } else if declared > current {
                self = .newer(declared)
            } else if declared.major < current.major {
                self = .incompatible(declared)
            } else {
                self = .older(declared)
            }
        }
    }
}

public extension AgentHome {
    /// Writes the template where no `settings.frame` exists; an existing
    /// file is never changed here.
    func prepareSettingsFile() throws {
        guard try settingsFileText() == nil else { return }
        try writeSettingsTemplate()
    }

    /// The declared schema alone, so a file whose fields no longer decode
    /// still says what it was written for.
    func settingsSchemaStanding() throws -> AgenticSettings.SchemaStanding {
        guard let text = try settingsFileText() else { return .missing }
        let document = try Frame.parse(
            text,
            filePath: layout.settingsfile.path,
            environment: FrameAgenticModule.environment
        )
        guard document.binding(named: "settings") != nil else { return .undeclared }
        let declared = try document.decode(DeclaredSchema.self, binding: "settings").schema
        return .init(declared: declared)
    }

    /// Archives `settings.frame` to `archive/` and writes the current
    /// template in its place. Returns the archived copy; nil when there was
    /// no file to archive.
    @discardableResult
    func modernizeSettingsFile(now: Date = Date()) throws -> URL? {
        var archived: URL?
        if let text = try settingsFileText() {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let stem = "settings-\(formatter.string(from: now))"
            // Runs within one second get -2, -3, ...
            var archive = layout.archivedir.appendingPathComponent("\(stem).frame")
            var count = 1
            while FileSystem.default.exists(archive) {
                count += 1
                archive = layout.archivedir.appendingPathComponent("\(stem)-\(count).frame")
            }
            try FileWriter(archive).write(text)
            archived = archive
        }
        try writeSettingsTemplate()
        return archived
    }

    private func settingsFileText() throws -> String? {
        let read = try TextFileReader(layout.settingsfile).read(
            options: .init(missingFilePolicy: .returnEmpty)
        )
        return read.text.isEmpty ? nil : read.text
    }

    private func writeSettingsTemplate() throws {
        try FileWriter(layout.settingsfile).write(
            AgenticSettingsTemplate.text,
            options: .overwriteWithoutBackup
        )
    }
}

/// `settings` read for its `.schema` alone; every other field is ignored.
private struct DeclaredSchema: Decodable {
    let schema: SemanticVersion?
}
