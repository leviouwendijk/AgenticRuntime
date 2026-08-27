import Agentic

public protocol AgenticApplicationProviding:
    Sendable
{
    static var application: AgenticApplication {
        get
    }
}
