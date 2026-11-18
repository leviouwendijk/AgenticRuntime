import CryptoKit
import Foundation

/// The `settings.frame` a home starts with: every setting commented out at
/// its default, so the file decodes to `AgenticSettings()` and shows what
/// can be set. Its first line marks the revision and a digest of the rest,
/// which tells an untouched template from an edited one.
///
/// Raise `revision` whenever `body` changes; a home whose file is an
/// untouched older template is then modernized on its next start.
public enum AgenticSettingsTemplate {
    public static let revision = 1

    public static let body = """
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

    /// The file as written: marker line, then `body`.
    public static var text: String {
        marker(revision: revision, digest: digest(body)) + "\n" + body
    }

    static let markerPrefix = "// agentic settings template "

    public static func marker(revision: Int, digest: String) -> String {
        "\(markerPrefix)\(revision) sha256:\(digest); edit freely, an edited file is never replaced"
    }

    public static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// What a `settings.frame` is, relative to the current template.
    public enum Standing: Sendable, Hashable {
        case missing
        /// The current template, untouched.
        case current
        /// An older template, untouched: safe to regenerate.
        case stale(revision: Int)
        /// Edited, or written by hand: left alone.
        case edited(revision: Int?)
    }

    public static func standing(of text: String?) -> Standing {
        guard let text, !text.isEmpty else { return .missing }
        guard let newline = text.firstIndex(of: "\n"),
              case let first = text[..<newline],
              first.hasPrefix(markerPrefix)
        else {
            return .edited(revision: nil)
        }
        let words = first.dropFirst(markerPrefix.count).split(separator: " ")
        guard words.count >= 2,
              let fileRevision = Int(words[0]),
              words[1].hasPrefix("sha256:")
        else {
            return .edited(revision: nil)
        }
        let recorded = words[1].dropFirst("sha256:".count).trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let rest = String(text[text.index(after: newline)...])
        guard digest(rest) == recorded else { return .edited(revision: fileRevision) }
        return fileRevision >= revision ? .current : .stale(revision: fileRevision)
    }
}

public extension AgentHome {
    /// What `prepareSettingsFile` did.
    enum SettingsPreparation: Sendable, Hashable {
        /// No file yet: the template was written.
        case written
        case current
        /// An untouched older template, archived and regenerated.
        case modernized(archive: URL)
        /// Edited and older than the template: left alone;
        /// `modernizeSettingsFile` replaces it on request.
        case outdated(revision: Int?)
        /// Edited, at the current revision.
        case edited
    }

    /// Writes the template where no `settings.frame` exists, and regenerates
    /// an untouched older template. An edited file is never replaced here.
    @discardableResult
    func prepareSettingsFile(now: Date = Date()) throws -> SettingsPreparation {
        switch AgenticSettingsTemplate.standing(of: try settingsFileText()) {
        case .missing:
            try writeSettingsTemplate()
            return .written
        case .current:
            return .current
        case .stale:
            guard let archive = try modernizeSettingsFile(now: now) else { return .written }
            return .modernized(archive: archive)
        case .edited(let revision):
            if let revision, revision >= AgenticSettingsTemplate.revision {
                return .edited
            }
            return .outdated(revision: revision)
        }
    }

    /// Archives `settings.frame` to `archive/` and writes the current
    /// template in its place. Returns the archived copy; nil when there was
    /// no file to archive.
    @discardableResult
    func modernizeSettingsFile(now: Date = Date()) throws -> URL? {
        var archived: URL?
        if let text = try settingsFileText(), !text.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let archive = layout.archivedir
                .appendingPathComponent("settings-\(formatter.string(from: now)).frame")
            try FileManager.default.createDirectory(at: layout.archivedir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: archive, options: .withoutOverwriting)
            archived = archive
        }
        try writeSettingsTemplate()
        return archived
    }

    private func settingsFileText() throws -> String? {
        let file = layout.settingsfile
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return String(decoding: try Data(contentsOf: file), as: UTF8.self)
    }

    private func writeSettingsTemplate() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(AgenticSettingsTemplate.text.utf8).write(to: layout.settingsfile, options: .atomic)
    }
}
