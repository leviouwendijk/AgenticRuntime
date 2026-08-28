import Foundation
import Milieu
import Path

public struct AgentHomeLocator: Sendable {
    public init() {}

    public func resolveHome(
        explicitRootURL: URL? = nil,
        allowLegacyHome: Bool = true
    ) -> AgentHome {
        if let explicitRootURL {
            return .init(
                root: explicitRootURL,
                kind: .user_global
            )
        }

        if let raw = AgenticEnvironmentVariable.agentic_home.optionalValue() {
            return .init(
                root: Self.expandedDirectoryURL(
                    raw
                ),
                kind: .user_global
            )
        }

        let canonical = Self.canonicalGlobalHomeURL()
        let legacy = Self.legacyHomeURL()

        if allowLegacyHome,
           !PathExistence.exists(url: canonical),
           PathExistence.exists(url: legacy) {
            return .init(
                root: legacy,
                kind: .user_global
            )
        }

        return .init(
            root: canonical,
            kind: .user_global
        )
    }

    public func resolveEphemeralHome() -> AgentHome {
        let temporaryRoot = StandardPath(
            fileURL: FileManager.default.temporaryDirectory,
            terminalHint: .directory,
            inferFileType: false
        )

        return .init(
            root: temporaryRoot
                .child
                .directory(
                    "agentic-\(UUID().uuidString)"
                )
                .directory_url,
            kind: .ephemeral
        )
    }

    public func findNearestProject(
        from startURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) -> AgentProjectDiscovery? {
        guard let match = PathLookup.nearestAncestorDirectory(
            named: ".agentic",
            from: startURL
        ) else {
            return nil
        }

        let layout = AgentProjectLayout(
            root: match.directoryURL
        )

        return .init(
            projectroot: match.ancestorURL,
            agenticdir: match.directoryURL,
            projectConfigurationExists: PathExistence.exists(
                url: layout.projectConfigurationFileURL
            ),
            localConfigurationExists: PathExistence.exists(
                url: layout.localConfigurationFileURL
            )
        )
    }

    public func loadProjectConfiguration(
        from discovery: AgentProjectDiscovery
    ) throws -> AgentProjectConfiguration? {
        guard discovery.projectConfigurationExists else {
            return nil
        }

        return try AgentProjectConfiguration.load(
            from: discovery.projectConfigurationFileURL
        )
    }

    public func loadProjectLocalConfiguration(
        from discovery: AgentProjectDiscovery
    ) throws -> AgentProjectLocalConfiguration? {
        guard discovery.localConfigurationExists else {
            return nil
        }

        return try AgentProjectLocalConfiguration.load(
            from: discovery.localConfigurationFileURL
        )
    }
}

public extension AgentHomeLocator {
    static func canonicalGlobalHomeURL() -> URL {
        if let raw = AgenticEnvironmentVariable.xdg_config_home.optionalValue(),
           let xdgConfigHome = try? PathResolver.resolveStandardPath(
                raw,
                relativeTo: .cwd,
                terminalHint: .directory
           ) {
            return xdgConfigHome
                .child
                .directory("agentic")
                .directory_url
        }

        return StandardPath.home
            .child
            .directory(
                ".config",
                "agentic"
            )
            .directory_url
    }

    static func legacyHomeURL() -> URL {
        StandardPath.home
            .child
            .directory(".agentic")
            .directory_url
    }
}

private extension AgentHomeLocator {
    static func expandedDirectoryURL(
        _ raw: String
    ) -> URL {
        if let url = try? PathResolver.resolveURL(
            raw,
            relativeTo: .cwd,
            terminalHint: .directory
        ) {
            return url.standardizedFileURL
        }

        return StandardPath.cwd.directory_url
    }
}
