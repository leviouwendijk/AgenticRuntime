import Foundation
import Path

public struct AgentRuntimeStorageTreeSchema: Sendable, Codable, Hashable {
    public let root: PathTreeDirectoryAddress

    public init(
        root: PathTreeDirectoryAddress = .root
    ) {
        self.root = root
    }

    public var sessionsdir: PathTreeDirectoryAddress {
        root.directory("sessions")
    }

    public var transcriptsdir: PathTreeDirectoryAddress {
        root.directory("transcripts")
    }

    public var approvalsdir: PathTreeDirectoryAddress {
        root.directory("approvals")
    }

    public var tasksdir: PathTreeDirectoryAddress {
        root.directory("tasks")
    }

    public var artifactsdir: PathTreeDirectoryAddress {
        root.directory("artifacts")
    }

    public var preparedintentsdir: PathTreeDirectoryAddress {
        root.directory("prepared-intents")
    }

    public var cachedir: PathTreeDirectoryAddress {
        root.directory("cache")
    }

    public var tmpdir: PathTreeDirectoryAddress {
        root.directory("tmp")
    }

    public func sessiondir(
        sessionID: String
    ) -> PathTreeDirectoryAddress {
        sessionsdir.directory(sessionID)
    }

    public func checkpointfile(
        sessionID: String
    ) -> PathTreeFileAddress {
        sessiondir(sessionID: sessionID)
            .file("checkpoint.json")
    }

    public func sessionstatefile(
        sessionID: String
    ) -> PathTreeFileAddress {
        sessiondir(sessionID: sessionID)
            .file("state.json")
    }

    public func transcriptfile(
        sessionID: String
    ) -> PathTreeFileAddress {
        transcriptsdir.file("\(sessionID).jsonl")
    }

    public func approvalsfile(
        sessionID: String
    ) -> PathTreeFileAddress {
        approvalsdir.file("\(sessionID).jsonl")
    }

    public func artifactdir(
        sessionID: String
    ) -> PathTreeDirectoryAddress {
        artifactsdir.directory(sessionID)
    }

    public var baseDirectories: [PathTreeDirectoryAddress] {
        [
            sessionsdir,
            transcriptsdir,
            approvalsdir,
            tasksdir,
            artifactsdir,
            preparedintentsdir,
            cachedir,
            tmpdir
        ]
    }

    public var gitIgnoreEntries: [String] {
        [
            "sessions/",
            "transcripts/",
            "approvals/",
            "tasks/",
            "cache/",
            "tmp/",
            "artifacts/",
            "prepared-intents/"
        ]
    }

    public var treeNodes: [PathTreeNode] {
        [
            .directory("sessions"),
            .directory("transcripts"),
            .directory("approvals"),
            .directory("tasks"),
            .directory("artifacts"),
            .directory("prepared-intents"),
            .directory("cache"),
            .directory("tmp")
        ]
    }
}

public struct AgentHomeTreeSchema: Sendable, Codable, Hashable {
    public let root: PathTreeDirectoryAddress
    public let storage: AgentRuntimeStorageTreeSchema

    public init(
        root: PathTreeDirectoryAddress = .root
    ) {
        self.root = root
        self.storage = AgentRuntimeStorageTreeSchema(
            root: root
        )
    }

    public var configfile: PathTreeFileAddress {
        root.file("config.json")
    }

    public var profilesdir: PathTreeDirectoryAddress {
        root.directory("profiles")
    }

    public var tree: PathTree {
        PathTree(root: root.path) {
            PathTreeNode.file("config.json")
            PathTreeNode.directory("profiles")
            storage.treeNodes
        }
    }
}

public struct AgentProjectTreeSchema: Sendable, Codable, Hashable {
    public let root: PathTreeDirectoryAddress
    public let storage: AgentRuntimeStorageTreeSchema

    public init(
        root: PathTreeDirectoryAddress = .root
    ) {
        self.root = root
        self.storage = AgentRuntimeStorageTreeSchema(
            root: root
        )
    }

    public var projectConfigurationFile: PathTreeFileAddress {
        root.file("project.json")
    }

    public var localConfigurationFile: PathTreeFileAddress {
        root.file("local.json")
    }

    public var localdir: PathTreeDirectoryAddress {
        root.directory("local")
    }

    public var initialDirectories: [PathTreeDirectoryAddress] {
        [
            root
        ]
    }

    public var gitIgnoreEntries: [String] {
        [
            "local.json",
            "local/"
        ] + storage.gitIgnoreEntries
    }

    public var projectRootGitIgnoreEntries: [String] {
        gitIgnoreEntries.map {
            ".agentic/\($0)"
        }
    }

    public var tree: PathTree {
        PathTree(root: root.path) {
            PathTreeNode.file("project.json")
            PathTreeNode.file("local.json")
            PathTreeNode.directory("local")
            storage.treeNodes
        }
    }
}
