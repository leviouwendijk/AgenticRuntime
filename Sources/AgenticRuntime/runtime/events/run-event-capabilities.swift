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
            /// A run before this one in the same conversation revealed it.
            case carried
            /// A tool's reveal grant, such as `inspect_capability`.
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
            /// `core` only where something was abbreviated.
            public let detail: ContextWindow.SchemaDetail
            /// The schema as sent.
            public let estimatedTokens: Int
            /// The schema in full; equal to `estimatedTokens` when sent full.
            public let fullTokens: Int

            public init(
                name: String,
                detail: ContextWindow.SchemaDetail,
                estimatedTokens: Int,
                fullTokens: Int
            ) {
                self.name = name
                self.detail = detail
                self.estimatedTokens = estimatedTokens
                self.fullTokens = fullTokens
            }
        }

        public let detail: ContextWindow.SchemaDetail
        public let reason: Reason
        public let entries: [Entry]
        /// The previous request advertised other tools, so the provider's
        /// cached prefix, which starts with them, is written again.
        public let rewritesCachedPrefix: Bool

        public init(
            detail: ContextWindow.SchemaDetail,
            reason: Reason,
            entries: [Entry],
            rewritesCachedPrefix: Bool
        ) {
            self.detail = detail
            self.reason = reason
            self.entries = entries
            self.rewritesCachedPrefix = rewritesCachedPrefix
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
