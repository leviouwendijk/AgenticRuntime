import Agentic
import AgenticWorkspace
import Foundation
import Path

public struct AgentRuntimeEnvironment: Sendable {
    public let home: AgentHome
    public let workspace: AgentWorkspace?
    public let projectDiscovery: AgentProjectDiscovery?
    public let projectConfiguration: AgentProjectConfiguration?
    public let projectLocalConfiguration: AgentProjectLocalConfiguration?
    public let sessionStorageMode: SessionStorageMode

    public init(
        home: AgentHome,
        workspace: AgentWorkspace? = nil,
        projectDiscovery: AgentProjectDiscovery? = nil,
        projectConfiguration: AgentProjectConfiguration? = nil,
        projectLocalConfiguration: AgentProjectLocalConfiguration? = nil,
        sessionStorageMode: SessionStorageMode = .global_home
    ) {
        self.home = home
        self.workspace = workspace
        self.projectDiscovery = projectDiscovery
        self.projectConfiguration = projectConfiguration
        self.projectLocalConfiguration = projectLocalConfiguration
        self.sessionStorageMode = sessionStorageMode
    }
}

public extension AgentRuntimeEnvironment {
    static func resolve(
        explicitHome: AgentHome? = nil,
        explicitHomeRootURL: URL? = nil,
        explicitWorkspace: AgentWorkspace? = nil,
        currentdir: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        sessionStorageMode explicitSessionStorageMode: SessionStorageMode? = nil,
        attachWorkspaceIfProjectDiscovered: Bool = true,
        createHomeDirectories: Bool = true
    ) throws -> Self {
        let locator = AgentHomeLocator()
        let projectDiscovery = locator.findNearestProject(
            from: currentdir
        )
        let projectConfiguration = try projectDiscovery.flatMap {
            try locator.loadProjectConfiguration(
                from: $0
            )
        }
        let projectLocalConfiguration = try projectDiscovery.flatMap {
            try locator.loadProjectLocalConfiguration(
                from: $0
            )
        }

        let home = explicitHome ?? locator.resolveHome(
            explicitRootURL: explicitHomeRootURL
        )

        if createHomeDirectories, home.kind != .ephemeral {
            try home.ensureBaseDirectoriesExist()
        }

        let effectiveSessionStorageMode = explicitSessionStorageMode
            ?? projectLocalConfiguration?.sessionStorageMode
            ?? projectConfiguration?.defaultSessionStorageMode
            ?? .global_home

        let workspace = try explicitWorkspace ?? resolvedWorkspace(
            projectDiscovery: projectDiscovery,
            projectConfiguration: projectConfiguration,
            attachWorkspaceIfProjectDiscovered: attachWorkspaceIfProjectDiscovered
        )

        return .init(
            home: home,
            workspace: workspace,
            projectDiscovery: projectDiscovery,
            projectConfiguration: projectConfiguration,
            projectLocalConfiguration: projectLocalConfiguration,
            sessionStorageMode: effectiveSessionStorageMode
        )
    }
}

private extension AgentRuntimeEnvironment {
    static func resolvedWorkspace(
        projectDiscovery: AgentProjectDiscovery?,
        projectConfiguration: AgentProjectConfiguration?,
        attachWorkspaceIfProjectDiscovered: Bool
    ) throws -> AgentWorkspace? {
        guard attachWorkspaceIfProjectDiscovered,
              let projectDiscovery else {
            return nil
        }

        let workspaceRootURL = resolveWorkspaceRootURL(
            projectRootURL: projectDiscovery.projectroot,
            rawWorkspaceRoot: projectConfiguration?.workspaceRoot
        )

        let root = StandardPath(
            fileURL: workspaceRootURL,
            terminalHint: .directory,
            inferFileType: false
        )

        return try AgentWorkspace(
            root: root
        )
    }

    static func resolveWorkspaceRootURL(
        projectRootURL: URL,
        rawWorkspaceRoot: String?
    ) -> URL {
        guard let rawWorkspaceRoot,
              !rawWorkspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return projectRootURL.standardizedFileURL
        }

        if let url = try? PathResolver.resolveURL(
            rawWorkspaceRoot,
            relativeTo: .directoryURL(projectRootURL),
            terminalHint: .directory
        ) {
            return url.standardizedFileURL
        }

        return StandardPath(
            fileURL: projectRootURL,
            terminalHint: .directory,
            inferFileType: false
        )
        .directory_url
    }
}

public extension AgentRuntimeEnvironment {
    func pricingCatalogpath() -> StandardPath? {
        switch sessionStorageMode {
        case .ephemeral:
            return nil

        case .global_home,
             .project_local,
             .custom:
            return home.rootPath.child.directory(
                "pricing"
            )
        }
    }

    func pricingCatalogdir() -> URL? {
        pricingCatalogpath()?.directory_url
    }

    func pricingCatalogfilePath(
        filename: String = "pricing-catalog.json"
    ) -> StandardPath? {
        pricingCatalogpath()?.child.file(
            filename
        )
    }

    func pricingCatalogfile(
        filename: String = "pricing-catalog.json"
    ) -> URL? {
        pricingCatalogfilePath(
            filename: filename
        )?.root_url
    }

    func createPricingCatalogDirectories() throws {
        guard let pricingCatalogpath = pricingCatalogpath() else {
            throw ModelPricingCatalogError.durableStorageRequired
        }

        try PathCreation.directory(
            pricingCatalogpath
        )
    }

    func filePricingCatalog(
        filename: String = "pricing-catalog.json",
        createDirectories: Bool = true
    ) throws -> FileModelPricingCatalog {
        if createDirectories {
            try createPricingCatalogDirectories()
        }

        guard let file = pricingCatalogfilePath(
            filename: filename
        ) else {
            throw ModelPricingCatalogError.durableStorageRequired
        }

        return FileModelPricingCatalog(
            catalogfile: file
        )
    }
}
