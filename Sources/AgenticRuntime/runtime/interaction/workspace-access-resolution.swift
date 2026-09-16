import AgenticWorkspace

public enum WorkspaceAccessResolution:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case deny
    case grant_for_turn
    case grant_for_session

    public var lifetime: PathGrantLifetime? {
        switch self {
        case .deny:
            return nil

        case .grant_for_turn:
            return .turn

        case .grant_for_session:
            return .session
        }
    }
}
