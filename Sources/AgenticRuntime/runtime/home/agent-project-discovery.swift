import Foundation

public struct AgentProjectDiscovery: Sendable, Codable, Hashable {
    public let projectroot: URL
    public let agenticdir: URL
    public let projectConfigurationExists: Bool
    public let localConfigurationExists: Bool

    public init(
        projectroot: URL,
        agenticdir: URL,
        projectConfigurationExists: Bool,
        localConfigurationExists: Bool
    ) {
        self.projectroot = projectroot.standardizedFileURL
        self.agenticdir = agenticdir.standardizedFileURL
        self.projectConfigurationExists = projectConfigurationExists
        self.localConfigurationExists = localConfigurationExists
    }

    public var layout: AgentProjectLayout {
        .init(
            root: agenticdir
        )
    }

    public var projectConfigurationFileURL: URL {
        layout.projectConfigurationFileURL
    }

    public var localConfigurationFileURL: URL {
        layout.localConfigurationFileURL
    }

    public var projectLocalHome: AgentHome {
        .init(
            root: agenticdir,
            kind: .project_local
        )
    }
}
