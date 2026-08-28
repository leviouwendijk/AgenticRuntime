import Agentic
import AgenticWorkspace
import Foundation

public enum AgenticRuntimeWorkspace {
    public static func resolve(
        _ rawPath: String
    ) throws -> AgentWorkspace {
        let normalized = rawPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !normalized.isEmpty else {
            throw AgenticRuntimeError.blankWorkspace
        }

        let expanded = NSString(
            string: normalized
        ).expandingTildeInPath

        let currentDirectory = URL(
            fileURLWithPath:
                FileManager.default.currentDirectoryPath,
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

        let root = candidate
            .standardizedFileURL
            .resolvingSymlinksInPath()

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue
        else {
            throw AgenticRuntimeError.invalidWorkspace(
                root.path
            )
        }

        return try AgentWorkspace(
            root: root
        )
    }
}
