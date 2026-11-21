import Agentic
import AgenticContext
import AgenticSensitivity
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
    /// Entries below memories/: what agents learned, unreviewed.
    public let memories: Int
    /// The oldest memory's `updated`, to see what has gone unreviewed.
    public let oldestMemory: String?
    public let problems: [String]
}

public extension ToolServices {
    /// The application's context store; nil when it supplies none.
    var contextStore: Context.Store? {
        try? require(Context.Store.self)
    }

    /// The owner's `.always` context entries as a system message, with
    /// their identifiers, followed by how to work with handles when a
    /// privacy guard is installed; nil when there is neither. Read on every
    /// run, so an entry saved mid-session reaches the next one.
    var contextEntries: (message: Message, ids: [String])? {
        let library = contextStore?.library()
        let parts = [
            library?.instructions,
            payloadGuardInstalled ? "# Sensitive values\n\n" + Privacy.Instructions.Handles.content : nil,
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return (Message(role: .system, text: parts.joined(separator: "\n\n")), library?.always.map(\.id) ?? [])
    }

    /// `contextEntries` with sensitive values in the owner's context
    /// replaced by handles, as it is sent and recorded; tools may still use
    /// them, since the owner supplied them.
    func guardedContextEntries() async -> (message: Message, ids: [String])? {
        guard let entries = contextEntries else { return nil }
        guard let shield = (try? require(ToolPayloadGuarding.self))?.shield,
              let text = entries.message.content.blocks.compactMap({ block -> String? in
                  if case .text(let text) = block { return text }
                  return nil
              }).first
        else {
            return entries
        }
        let protected = await shield.protecting(text, from: ToolIdentifier("context"))
        return (Message(role: .system, text: protected), entries.ids)
    }

    /// Whether tool payloads pass a guard in this session.
    var payloadGuardInstalled: Bool {
        (try? require(ToolPayloadGuarding.self)) != nil
    }

    var contextSummary: ContextEntrySummary? {
        guard let library = contextStore?.library() else { return nil }
        let memories = library.items.filter { Context.isMemoryFile($0.file) }
        return .init(
            directory: library.directory.path,
            entries: library.items.count,
            always: library.always.map(\.id),
            alwaysTokens: library.instructions.map { TokenEstimator.estimate($0).estimatedTokens } ?? 0,
            memories: memories.count,
            oldestMemory: memories.compactMap(\.entry.updated).min(),
            problems: library.problems
        )
    }
}

public extension AgentCapabilitySet {
    /// Granted to every agent, beyond what it declares, when the
    /// application installs them: reading the owner's context, remembering
    /// and forgetting memories (only below memories/), describing handles
    /// and asking the owner for one. Writing curated context stays with
    /// agents that declare `context_save`.
    static let ambient = AgentCapabilitySet(
        tools: [
            Context.Tools.Index.identifier,
            Context.Tools.Read.identifier,
            Context.Tools.Search.identifier,
            Context.Tools.Remember.identifier,
            Context.Tools.Forget.identifier,
            Privacy.Tools.Handles.identifier,
            Privacy.Tools.Grant.identifier,
        ]
    )
}
