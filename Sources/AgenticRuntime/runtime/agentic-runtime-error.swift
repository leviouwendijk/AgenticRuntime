import Foundation

public enum AgenticRuntimeError:
    Error,
    Sendable,
    LocalizedError
{
    case invalidWorkspace(String)
    case blankWorkspace

    public var errorDescription: String? {
        switch self {
        case .invalidWorkspace(let path):
            return "Workspace does not exist or is not a directory: \(path)"

        case .blankWorkspace:
            return "Workspace path cannot be blank."
        }
    }
}
