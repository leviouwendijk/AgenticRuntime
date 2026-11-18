import Agentic
import AgenticContext
import Tokens

/// What the owner's context holds for a session: for diagnostics, and the
/// `.always` entries every run receives.
public struct ContextEntrySummary: Sendable, Hashable {
    public let directory: String
    public let entries: Int
    /// Identifiers of the `.always` entries.
    public let always: [String]
    /// Estimated size of the message they make.
    public let alwaysTokens: Int
    public let problems: [String]
}

public extension ToolServices {
    /// The application's context store; nil when it supplies none.
    var contextStore: Context.Store? {
        try? require(Context.Store.self)
    }

    /// The owner's `.always` context entries as a system message, with
    /// their identifiers; nil without a store or without such entries. Read
    /// on every run, so an entry saved mid-session reaches the next one.
    var contextEntries: (message: Message, ids: [String])? {
        guard let library = contextStore?.library(),
              let instructions = library.instructions
        else {
            return nil
        }
        return (Message(role: .system, text: instructions), library.always.map(\.id))
    }

    var contextSummary: ContextEntrySummary? {
        guard let library = contextStore?.library() else { return nil }
        return .init(
            directory: library.directory.path,
            entries: library.items.count,
            always: library.always.map(\.id),
            alwaysTokens: library.instructions.map { TokenEstimator.estimate($0).estimatedTokens } ?? 0,
            problems: library.problems
        )
    }
}

public extension AgentCapabilitySet {
    /// Granted to every agent, beyond what it declares, when the
    /// application installs them: reading the owner's context. Writing it
    /// stays with agents that declare `context_save`.
    static let ambient = AgentCapabilitySet(
        tools: [
            Context.Tools.Index.identifier,
            Context.Tools.Read.identifier,
        ]
    )
}
