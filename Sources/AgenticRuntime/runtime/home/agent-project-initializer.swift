import Foundation
import Path

public enum AgentProjectInitializer {
    public static func initialize(
        projectroot: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        configuration: AgentProjectConfiguration = .init(),
        createLocalGitIgnoreEntries: Bool = true
    ) throws -> AgentProjectDiscovery {
        let rootPath = StandardPath(
            fileURL: projectroot,
            terminalHint: .directory,
            inferFileType: false
        )
        let agenticPath = rootPath.child.directory(
            ".agentic"
        )
        let layout = AgentProjectLayout(
            root: agenticPath.directory_url
        )

        try layout.createInitialDirectories()

        if !PathExistence.exists(
            url: layout.projectConfigurationFileURL
        ) {
            try configuration.write(
                to: layout.projectConfigurationFileURL
            )
        }

        if createLocalGitIgnoreEntries {
            try ensureGitIgnoreEntries(
                projectroot: rootPath,
                entries: layout.projectRootGitIgnoreEntries
            )
        }

        return .init(
            projectroot: rootPath.directory_url,
            agenticdir: agenticPath.directory_url,
            projectConfigurationExists: true,
            localConfigurationExists: PathExistence.exists(
                url: layout.localConfigurationFileURL
            )
        )
    }
}

private extension AgentProjectInitializer {
    static func ensureGitIgnoreEntries(
        projectroot: StandardPath,
        entries: [String]
    ) throws {
        let gitdir = projectroot.child.directory(
            ".git"
        )

        guard PathExistence.isDirectory(
            url: gitdir.directory_url
        ) else {
            return
        }

        let gitIgnoreURL = projectroot
            .child
            .file(".gitignore")
            .root_url

        let existing: String
        if PathExistence.exists(
            url: gitIgnoreURL
        ) {
            existing = try String(
                contentsOf: gitIgnoreURL,
                encoding: .utf8
            )
        } else {
            existing = ""
        }

        let existingLines = Set(
            existing
                .split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                )
                .map {
                    String($0).trimmingCharacters(
                        in: .whitespaces
                    )
                }
        )

        let missing = entries.filter {
            !existingLines.contains($0)
        }

        guard !missing.isEmpty else {
            return
        }

        var updated = existing

        if !updated.isEmpty,
           !updated.hasSuffix("\n") {
            updated += "\n"
        }

        updated += "\n# Agentic private runtime state\n"
        updated += missing.joined(
            separator: "\n"
        )
        updated += "\n"

        try updated.write(
            to: gitIgnoreURL,
            atomically: true,
            encoding: .utf8
        )
    }
}
