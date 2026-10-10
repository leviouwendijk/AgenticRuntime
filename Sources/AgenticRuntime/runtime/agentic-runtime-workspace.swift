import Agentic
import IO
import Foundation
import Path
import Workspace

public enum AgenticRuntimeWorkspace {
    public static func resolve(
        _ rawPath: String
    ) throws -> Workspace {
        try resolve(
            .init(
                path: rawPath
            )
        )
    }

    public static func resolve(
        _ configuration: AgenticRuntimeWorkspaceConfiguration
    ) throws -> Workspace {
        let normalized = configuration.path
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !normalized.isEmpty else {
            throw AgenticRuntimeError.blankWorkspace
        }

        let expanded = NSString(
            string: normalized
        ).expandingTildeInPath

        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        let candidate: URL

        if expanded.hasPrefix("/") {
            candidate = URL(
                fileURLWithPath: expanded,
                isDirectory: true
            )
        } else {
            candidate = URL(
                fileURLWithPath: expanded,
                isDirectory: true,
                relativeTo: currentDirectory
            )
        }

        let rootURL = candidate
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard (try? FileInspector(rootURL).inspect().kind) == .directory
        else {
            throw AgenticRuntimeError.invalidWorkspace(
                rootURL.path
            )
        }

        let rootIdentifier = PathAccessRootIdentifier(
            rawValue: "project"
        )
        let root = PathAccessRoot(
            id: rootIdentifier,
            label: "Project",
            scope: try PathAccessScope(
                root: rootURL,
                policy: .defaults.workspace
            ),
            isDefault: true
        )
        let grant = try WorkspaceGrant(
            id: WorkspaceGrantIdentifier(
                "project-runtime"
            ),
            rootIdentifier: rootIdentifier,
            capabilities: Set(WorkspaceCapability.allCases)
        )

        return try Workspace(
            root: root,
            grants: [grant]
        )
    }
}
