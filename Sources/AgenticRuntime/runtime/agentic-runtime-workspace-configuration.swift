import Foundation

public struct AgenticRuntimeWorkspaceConfiguration:
    Sendable,
    Codable,
    Hashable
{
    public let path: String

    public init(
        path: String
    ) {
        self.path = path.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}
