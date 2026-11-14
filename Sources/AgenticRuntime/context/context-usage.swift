import Agentic
import Foundation
import Tokens

public extension Context {
    /// Estimated input tokens of one model turn, by what they were spent on.
    struct Usage: Sendable, Codable, Hashable {
        /// The model turn this request was sent for.
        public let turn: Int
        /// System messages.
        public var instructions: Int
        /// Advertised function schemas.
        public var tools: Int
        /// User and assistant text.
        public var conversation: Int
        /// Function calls the model made earlier in the conversation.
        public var calls: Int
        /// Responses returned for those calls.
        public var results: Int
        /// Attached resources (references only; bytes are not inlined).
        public var resources: Int

        public var total: Int {
            instructions + tools + conversation + calls + results + resources
        }

        public init(
            turn: Int,
            request: AgentRequest,
            options: TokenEstimationOptions = .agenticContext
        ) {
            func estimate(_ text: String) -> Int {
                text.isEmpty ? 0 : TokenEstimator.estimate(text, options: options).estimatedTokens
            }

            func estimate(_ value: some Encodable) -> Int {
                guard let data = try? Self.encoder.encode(value) else {
                    return 0
                }
                return estimate(String(decoding: data, as: UTF8.self))
            }

            self.turn = turn
            self.instructions = 0
            self.tools = request.tools.reduce(0) { $0 + estimate($1) }
            self.conversation = 0
            self.calls = 0
            self.results = 0
            self.resources = 0

            for message in request.messages {
                for block in message.content.blocks {
                    switch block {
                    case .text(let text) where message.role == .system:
                        instructions += estimate(text)
                    case .text(let text):
                        conversation += estimate(text)
                    case .call(let call):
                        calls += estimate(call)
                    case .result(let response):
                        results += estimate(response.modelText)
                    case .resource(let resource):
                        resources += estimate(resource)
                    }
                }
            }
        }

        /// One line for run events, e.g. `48k in: tools 9k · results 31k · …`.
        public var summary: String {
            let parts = [
                ("instructions", instructions),
                ("tools", tools),
                ("conversation", conversation),
                ("calls", calls),
                ("results", results),
                ("resources", resources),
            ]
            .filter { $0.1 > 0 }
            .map { "\($0.0) \(Self.compact($0.1))" }

            return "\(Self.compact(total)) in: " + parts.joined(separator: " · ")
        }

        private static let encoder: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return encoder
        }()

        private static func compact(_ tokens: Int) -> String {
            tokens >= 1_000
                ? String(format: "%.1fk", Double(tokens) / 1_000)
                : String(tokens)
        }
    }
}
