import Foundation
import Path

public struct AgentHome: Sendable, Codable, Hashable {
    public let root: URL
    public let kind: AgentHomeKind

    public init(
        root: URL,
        kind: AgentHomeKind
    ) {
        self.root = root.standardizedFileURL
        self.kind = kind
    }

    public var layout: AgentHomeLayout {
        .init(
            root: root
        )
    }

    public func ensureBaseDirectoriesExist() throws {
        try layout.createBaseDirectories()
    }

    public func ensureSessionDirectoriesExist(
        sessionID: String
    ) throws {
        try layout.createSessionDirectories(
            sessionID: sessionID
        )
    }

    public var rootPath: StandardPath {
        StandardPath(
            fileURL: root,
            terminalHint: .directory,
            inferFileType: false
        )
    }
}
