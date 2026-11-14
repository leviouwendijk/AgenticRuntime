import Agentic
import Foundation
import Primitives

public extension Run.Log {
    /// A session as a conversation: what was said, called and returned, in
    /// order, with delegated runs nested under the run that started them.
    /// Built from the log and its payloads only.
    struct Replay: Sendable, Hashable {
        public struct Item: Sendable, Hashable {
            public let seq: Int
            public let time: Date
            public let run: String?
            /// 0 for the session's own runs, +1 per delegation.
            public let depth: Int
            public let event: Event
        }

        public enum Event: Sendable, Hashable {
            /// Text a message carried; tool calls and results appear as
            /// `call` and `response`.
            case message(role: MessageRole, text: String)
            case call(FunctionCall.Reference, input: JSONValue)
            case response(FunctionCall.Reference, output: JSONValue, isError: Bool)
            /// A delegated run started from `parent`.
            case branch(parent: String)
            /// What a model turn cost.
            case cost(String)
            /// A run event worth seeing in a replay: limits, failures,
            /// denials, interruptions, publication.
            case notice(Run.Event.State.Kind, String)
        }

        public let items: [Item]

        static let notices: Set<Run.Event.State.Kind> = [
            .run_failed, .run_limit_reached, .run_limit_stopped, .run_interrupted,
            .compaction, .model_stream_interrupted, .model_stream_failed,
            .tool_denied, .tool_skipped,
            .pending_approval, .pending_user_input, .pending_workspace_access,
            .mutation_staged, .mutation_published, .mutation_withdrawn,
        ]
    }
}

public extension Run.Log.Store {
    /// The session as a conversation. `run` keeps only runs whose ID
    /// contains it; a delegated run's ID contains its parent's, so a parent
    /// run keeps its children.
    func replay(
        session: String,
        run reference: String? = nil
    ) throws -> Run.Log.Replay {
        let contents = try read(session: session)
        var depths: [String: Int] = [:]
        var items: [Run.Log.Replay.Item] = []

        for entry in contents.entries {
            if case .branch(let event) = entry.body {
                depths[event.sessionID] = (depths[event.branch.parentSessionID] ?? 0) + 1
            }
            if let reference, !(entry.run ?? "").contains(reference) {
                continue
            }
            guard let event = try replayEvent(entry, session: session) else {
                continue
            }
            items.append(
                .init(
                    seq: entry.seq,
                    time: entry.time,
                    run: entry.run,
                    depth: entry.run.flatMap { depths[$0] } ?? 0,
                    event: event
                )
            )
        }
        return .init(items: items)
    }

    /// The entry's one-line summary; a message also says who spoke and how
    /// it starts.
    func summary(
        of entry: Run.Log.Entry,
        session: String
    ) -> String {
        guard case .message(let stored) = entry.body,
              let message = try? payload(stored.digest, as: Message.self, session: session)
        else {
            return entry.summary
        }
        let text = Self.text(of: message)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        let calls = message.content.blocks.compactMap { block -> String? in
            if case .call(let call) = block { return "→ " + call.name }
            return nil
        }
        let preview = text.count > 120 ? String(text.prefix(119)) + "…" : text
        return ([message.role.rawValue, preview] + calls)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private extension Run.Log.Store {
    func replayEvent(
        _ entry: Run.Log.Entry,
        session: String
    ) throws -> Run.Log.Replay.Event? {
        switch entry.body {
        case .message(let stored):
            let message = try payload(stored.digest, as: Message.self, session: session)
            let text = Self.text(of: message)
            guard !text.isEmpty else { return nil }
            return .message(role: message.role, text: text)
        case .call(let call):
            return .call(
                call.call,
                input: try payload(call.input, as: JSONValue.self, session: session)
            )
        case .response(let stored):
            let response = try payload(stored.digest, as: FunctionCall.Response.self, session: session)
            return .response(response.call, output: response.output, isError: response.isError)
        case .branch(let event):
            return .branch(parent: event.branch.parentSessionID)
        case .state(let state) where state.kind == .cost_actual:
            return .cost(state.summary)
        case .state(let state) where Run.Log.Replay.notices.contains(state.kind):
            return .notice(state.kind, state.summary)
        case .state, .observation, .request:
            return nil
        }
    }

    static func text(of message: Message) -> String {
        message.content.blocks.compactMap { block -> String? in
            if case .text(let text) = block { return text }
            return nil
        }.joined()
    }
}
