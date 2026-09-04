import AgenticWorkspace
import Foundation

public struct AgenticRuntimeWorkspaceConfiguration:
    Sendable,
    Codable,
    Hashable
{
    public let path: String
    public let selection: WorkspaceSelection

    public init(
        path: String,
        selection: WorkspaceSelection = .all
    ) {
        self.path = path.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.selection = selection
    }

    public init(
        path: String,
        exactPaths: [String] = [],
        includeExpressions: [String] = [],
        excludeExpressions: [String] = []
    ) throws {
        self.init(
            path: path,
            selection: try WorkspaceSelection(
                exactPaths: exactPaths,
                includeExpressions: includeExpressions,
                excludeExpressions: excludeExpressions
            )
        )
    }
}
