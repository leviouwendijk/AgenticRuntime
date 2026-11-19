import Agentic
import AgenticContextWindow
import Foundation

public extension Run {
    /// Typed outer runtime event channel.
    ///
    /// In this pass the channel carries exactly two payloads:
    ///   - `state` — the durable run-state summary record (the canonical
    ///     replacement for the former `Run.Event.State`).
    ///   - `tool_observation` — a live tool execution observation.
    enum Event: Sendable, Codable, Hashable {
        case state(State)
        case tool_observation(ToolResultObservation)
        /// The exact request sent to the model for a turn.
        case request(Request)
    }
}

public extension Run.Event {
    struct Request: Sendable, Codable, Hashable {
        public let request: AgentRequest
        public let usage: ContextWindow.Usage

        public init(request: AgentRequest, usage: ContextWindow.Usage) {
            self.request = request
            self.usage = usage
        }
    }
}

public extension Run.Event {
    /// Durable run-state summary record.
    ///
    /// The encoded shape is structurally identical to the former
    /// `Run.Event.State` so that existing checkpoint JSON remains decodable.
    struct State: Sendable, Codable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Codable, Hashable, CaseIterable {
            case assistant_response
            case run_failed
            case run_limit_reached
            case run_limit_continued
            case run_limit_stopped
            case run_interrupted
            case compaction
            case context_usage
            case model_stream_started
            case assistant_delta
            case model_stream_tool_call
            case model_stream_completed
            case model_stream_interrupted
            case model_stream_failed
            case tool_preflight
            case tool_approved
            case tool_denied
            case tool_skipped
            case pending_approval
            case pending_user_input
            case pending_workspace_access
            case tool_result
            case tool_error
            case cost_projected
            case cost_actual
            /// Coordinated mutation lifecycle: staged under claims, then
            /// published to disk or withdrawn.
            case mutation_staged
            case mutation_published
            case mutation_withdrawn
            /// An operator's command, as typed, with its outcome.
            case operator_command
            /// Workspace access changed: a root added, revoked, expired or
            /// restricted, or the default root moved.
            case workspace_changed
            /// A delegated child's report failed its output contract and was
            /// asked for once more, without tools; the summary says how it went.
            case output_repaired
            /// Operator input joined the run at a model boundary (steering).
            case input_applied
            /// A request carries less of the history than the transcript
            /// holds: results shortened or pointed at, exchanges or turns
            /// left out. `contextChanges` names each, with its reason.
            case context_changed
            /// A request passed its soft input limit: advice to compact,
            /// with what it would save. Nothing changes on its own.
            case context_pressure
            /// Which model served a request; `route` says whether it is
            /// the one selected, and if not, why.
            case model_routed
            /// Capabilities entered or left the Agent's authority or the
            /// model's view; `capabilityChanges` names each and its source.
            case capability_changed
            /// A request advertised other function schemas than the one
            /// before; `advertisement` gives each, its form and its cost.
            case schemas_advertised
        }

        public let id: String
        public let kind: Kind
        public let iteration: Int
        public let messageID: String?
        public let callID: String?
        public let toolName: String?
        public let summary: String
        /// For `context_changed`: the decisions this request newly made.
        public let contextChanges: [ContextWindow.HistorySelection.Change]?
        /// For `model_routed`: the model that served the request.
        public let route: Run.Event.Route?
        /// For `capability_changed`: what changed, and what changed it.
        public let capabilityChanges: [Run.Event.CapabilityChange]?
        /// For `schemas_advertised`: the schemas the request carried.
        public let advertisement: Run.Event.Advertisement?

        public init(
            id: String = UUID().uuidString,
            kind: Kind,
            iteration: Int,
            messageID: String? = nil,
            callID: String? = nil,
            toolName: String? = nil,
            summary: String,
            contextChanges: [ContextWindow.HistorySelection.Change]? = nil,
            route: Run.Event.Route? = nil,
            capabilityChanges: [Run.Event.CapabilityChange]? = nil,
            advertisement: Run.Event.Advertisement? = nil
        ) {
            self.contextChanges = contextChanges
            self.route = route
            self.capabilityChanges = capabilityChanges
            self.advertisement = advertisement
            self.id = id
            self.kind = kind
            self.iteration = iteration
            self.messageID = messageID
            self.callID = callID
            self.toolName = toolName
            self.summary = summary
        }
    }
}

// MARK: - Deprecated compatibility aliases

