import Agentic

public extension Run.Event {
    /// One capability entering or leaving the Agent's authority (`enabled`,
    /// `disabled`) or the model's view (`exposed`, `hidden`), and what did it.
    struct CapabilityChange: Sendable, Codable, Hashable {
        public enum Operation: String, Sendable, Codable, Hashable {
            case enabled
            case disabled
            case exposed
            case hidden
        }

        public enum Source: String, Sendable, Codable, Hashable {
            /// The Agent's declaration, as the run's first request found it.
            case declared
            /// The grants (`AgentCapabilityGrant`), applied before the first request.
            case ambient
            case discovery
            case session_readers
            case result_reader
            case friction_notes
            /// Recorded by runs before inspection became read-only
            /// (2026-11-19): a reveal an earlier run carried over.
            case carried
            /// Recorded by runs before inspection became read-only
            /// (2026-11-19): `capabilities_tool_inspect` revealed it.
            case tool_reveal
            /// Anything outside the loop: the host, an operator, settings.
            case other

            public init(_ grant: AgentCapabilityGrant) {
                switch grant {
                case .ambient: self = .ambient
                case .discovery: self = .discovery
                case .session_readers: self = .session_readers
                case .result_reader: self = .result_reader
                case .friction_notes: self = .friction_notes
                }
            }
        }

        public let reference: CapabilityReference
        public let operation: Operation
        public let source: Source

        public init(
            reference: CapabilityReference,
            operation: Operation,
            source: Source
        ) {
            self.reference = reference
            self.operation = operation
            self.source = source
        }
    }

    /// The function schemas a request advertised, recorded when they differ
    /// from the previous request's, with what each one costs.
    struct Advertisement: Sendable, Codable, Hashable {
        public enum Reason: String, Sendable, Codable, Hashable {
            /// The context policy asks for full schemas.
            case policy_full
            /// Core form: the inspector returns the rest.
            case core
            /// Core form was asked for, but the inspector is not available.
            case inspector_unavailable
        }

        public struct Entry: Sendable, Codable, Hashable {
            public let name: String
            /// The capability declared under `name`; nil in older records.
            public let reference: CapabilityReference?
            /// `core` only where something was abbreviated.
            public let detail: ContextWindow.SchemaDetail
            /// The schema as sent.
            public let estimatedTokens: Int
            /// The schema in full; equal to `estimatedTokens` when sent full.
            public let fullTokens: Int

            public init(
                name: String,
                reference: CapabilityReference?,
                detail: ContextWindow.SchemaDetail,
                estimatedTokens: Int,
                fullTokens: Int
            ) {
                self.name = name
                self.reference = reference
                self.detail = detail
                self.estimatedTokens = estimatedTokens
                self.fullTokens = fullTokens
            }
        }

        /// What the visible set adds to or drops from the declared tools,
        /// waiting for a refresh: the definitions stay fixed until the
        /// cached prefix is lost anyway (compaction, expiry, a model switch)
        /// or the operator applies it.
        public struct Pending: Sendable, Codable, Hashable {
            public let added: [String]
            public let removed: [String]

            public init(added: [String], removed: [String]) {
                self.added = added
                self.removed = removed
            }

            public var isEmpty: Bool {
                added.isEmpty && removed.isEmpty
            }
        }

        public let detail: ContextWindow.SchemaDetail
        public let reason: Reason
        public let entries: [Entry]
        /// Available capabilities callable without a definition: by name or
        /// through `capabilities_tool_call`, their contracts from
        /// `capabilities_tool_inspect`.
        public let callable: Int
        public let pending: Pending?
        /// This request rebuilt the definitions from the visible set,
        /// applying what was pending.
        public let refreshed: Bool
        /// The previous request advertised other tools, so the provider's
        /// cached prefix, which starts with them, is written again.
        public let rewritesCachedPrefix: Bool

        public init(
            detail: ContextWindow.SchemaDetail,
            reason: Reason,
            entries: [Entry],
            callable: Int = 0,
            pending: Pending? = nil,
            refreshed: Bool = false,
            rewritesCachedPrefix: Bool
        ) {
            self.detail = detail
            self.reason = reason
            self.entries = entries
            self.callable = callable
            self.pending = pending.flatMap { $0.isEmpty ? nil : $0 }
            self.refreshed = refreshed
            self.rewritesCachedPrefix = rewritesCachedPrefix
        }

        private enum CodingKeys: String, CodingKey {
            case detail, reason, entries, callable, pending, refreshed, rewritesCachedPrefix
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                detail: try container.decode(ContextWindow.SchemaDetail.self, forKey: .detail),
                reason: try container.decode(Reason.self, forKey: .reason),
                entries: try container.decode([Entry].self, forKey: .entries),
                callable: try container.decodeIfPresent(Int.self, forKey: .callable) ?? 0,
                pending: try container.decodeIfPresent(Pending.self, forKey: .pending),
                refreshed: try container.decodeIfPresent(Bool.self, forKey: .refreshed) ?? false,
                rewritesCachedPrefix: try container.decode(Bool.self, forKey: .rewritesCachedPrefix)
            )
        }

        public var estimatedTokens: Int {
            entries.reduce(0) { $0 + $1.estimatedTokens }
        }

        public var fullTokens: Int {
            entries.reduce(0) { $0 + $1.fullTokens }
        }
    }
}

public extension CapabilityReference {
    /// The identifier, whatever the kind: the name a change is shown by.
    var identifier: String {
        switch self {
        case .tool(let identifier): identifier.rawValue
        case .program(let identifier): identifier.rawValue
        case .inference(let identifier): identifier.rawValue
        case .agent(let identifier): identifier.rawValue
        }
    }
}
