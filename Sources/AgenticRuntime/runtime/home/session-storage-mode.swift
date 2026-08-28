import Foundation

public enum SessionStorageMode: Sendable, Codable, Hashable {
    case global_home
    case project_local
    case ephemeral
    case custom(URL)
}

public extension SessionStorageMode {
    var isDurable: Bool {
        switch self {
        case .global_home,
             .project_local,
             .custom:
            return true

        case .ephemeral:
            return false
        }
    }
}
