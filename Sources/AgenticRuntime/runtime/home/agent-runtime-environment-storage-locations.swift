import AgenticConfiguration
import Foundation

public struct AgentRuntimeStorageLocations: Sendable, Codable, Hashable {
    public let sessionsdir: URL?
    public let transcriptsdir: URL?
    public let approvalsdir: URL?
    public let artifactsdir: URL?
    public let tasksdir: URL?
    public let intentsdir: URL?

    public init(
        sessionsdir: URL? = nil,
        transcriptsdir: URL? = nil,
        approvalsdir: URL? = nil,
        artifactsdir: URL? = nil,
        tasksdir: URL? = nil,
        intentsdir: URL? = nil
    ) {
        self.sessionsdir = sessionsdir
        self.transcriptsdir = transcriptsdir
        self.approvalsdir = approvalsdir
        self.artifactsdir = artifactsdir
        self.tasksdir = tasksdir
        self.intentsdir = intentsdir
    }
}

public extension AgentRuntimeEnvironment {
    func storageLocations() -> AgentRuntimeStorageLocations {
        guard let layout = runtimeStorageLayout() else {
            return .init()
        }

        return .init(
            sessionsdir: layout.sessionsdir,
            transcriptsdir: layout.transcriptsdir,
            approvalsdir: layout.approvalsdir,
            artifactsdir: layout.artifactsdir,
            tasksdir: layout.tasksdir,
            intentsdir: layout.intentsdir
        )
    }

    func sessionsdir() -> URL? {
        storageLocations().sessionsdir
    }

    func transcriptsdir() -> URL? {
        storageLocations().transcriptsdir
    }

    func approvalsdir() -> URL? {
        storageLocations().approvalsdir
    }

    func artifactsdir() -> URL? {
        storageLocations().artifactsdir
    }

    func tasksdir() -> URL? {
        storageLocations().tasksdir
    }

    func intentsdir() -> URL? {
        storageLocations().intentsdir
    }

    func sessiondir(
        sessionID: String
    ) -> URL? {
        runtimeStorageLayout()?
            .sessiondir(
                sessionID: sessionID
            )
    }

    func checkpointfile(
        sessionID: String
    ) -> URL? {
        runtimeStorageLayout()?
            .checkpointfile(
                sessionID: sessionID
            )
    }

    func sessionstatefile(
        sessionID: String
    ) -> URL? {
        runtimeStorageLayout()?
            .sessionstatefile(
                sessionID: sessionID
            )
    }

    func transcriptfile(
        sessionID: String
    ) -> URL? {
        runtimeStorageLayout()?
            .transcriptfile(
                sessionID: sessionID
            )
    }

    func approvalsfile(
        sessionID: String
    ) -> URL? {
        runtimeStorageLayout()?
            .approvalsfile(
                sessionID: sessionID
            )
    }

    func artifactdir(
        sessionID: String
    ) -> URL? {
        runtimeStorageLayout()?
            .artifactdir(
                sessionID: sessionID
            )
    }

    func createSessionDirectories(
        sessionID: String
    ) throws {
        try runtimeStorageLayout()?
            .createSessionDirectories(
                sessionID: sessionID
            )
    }
}

extension AgentRuntimeEnvironment {
    func runtimeStorageLayout() -> AgentRuntimeStorageLayout? {
        switch sessionStorageMode {
        case .global_home:
            return home.layout.runtimeStorage

        case .project_local:
            return projectDiscovery?.layout.runtimeStorage

        case .custom(let rootURL):
            return AgentRuntimeStorageLayout(
                root: rootURL
            )

        case .ephemeral:
            return nil
        }
    }
}
