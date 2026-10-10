import Agentic
import Foundation
import Tokens

public enum ContextInferenceError: Error, Equatable {
    case noCurrentUserMessage
    case foreignSystemMessage(String)
    case foreignUserMessage(String)
    case foreignToolMessage(String)
    case conflictingMessageID(String)
    case unpairedToolResult(String)
    case duplicateToolCall(String)
    case inputBudgetExceeded(estimated: Int, maximum: Int)
    case invalidInputBudget(Int)
    case requiredHistoryExceedsTailBudget(estimated: Int, maximum: Int)
}

public extension Context {
    /// Preparation changes one inference request, never the durable session state.
    enum InferenceDelivery: String, Sendable, Codable, Hashable {
        /// Keep the current dialogue and supplement it with selected evidence.
        case supplement
        /// Preserve system messages and the dialogue from the most recent user
        /// turn, but replace older active history with the selected evidence.
        case working_set
        /// Deterministic complete-turn tail controlled by the allocator.
        case dynamic
    }

    struct HistorySelection: Sendable, Codable, Hashable {
        /// Checkpoint message indices are stable while the source history is
        /// append-only. These are references, not retained text copies.
        public struct Reference: Sendable, Codable, Hashable {
            public let index: Int
            public let messageID: String
        }
        public let retained: [Reference]
        public let omitted: [Reference]
    }

    struct InferenceMeasurement: Sendable, Codable, Hashable {
        public let selectedAllocations: Int
        public let skippedAllocations: Int
        public let distinctSources: Int
        public let messageCount: Int
        public let toolDefinitionCount: Int
        public let toolCallCount: Int
        public let toolResultCount: Int
        public let serializedRequestBytes: Int
        public let estimatedInputTokens: Int
        public let maximumInputTokens: Int

        public init(
            selectedAllocations: Int,
            skippedAllocations: Int,
            distinctSources: Int,
            messageCount: Int,
            toolDefinitionCount: Int,
            toolCallCount: Int,
            toolResultCount: Int,
            serializedRequestBytes: Int,
            estimatedInputTokens: Int,
            maximumInputTokens: Int
        ) {
            self.selectedAllocations = selectedAllocations
            self.skippedAllocations = skippedAllocations
            self.distinctSources = distinctSources
            self.messageCount = messageCount
            self.toolDefinitionCount = toolDefinitionCount
            self.toolCallCount = toolCallCount
            self.toolResultCount = toolResultCount
            self.serializedRequestBytes = serializedRequestBytes
            self.estimatedInputTokens = estimatedInputTokens
            self.maximumInputTokens = maximumInputTokens
        }
    }

    struct InferencePreparation: Sendable, Codable, Hashable {
        public let request: AgentRequest
        public let frame: Frame
        public let delivery: InferenceDelivery
        public let measurement: InferenceMeasurement
        public let history: HistorySelection

        public init(
            request: AgentRequest,
            frame: Frame,
            delivery: InferenceDelivery,
            measurement: InferenceMeasurement,
            history: HistorySelection
        ) {
            self.request = request
            self.frame = frame
            self.delivery = delivery
            self.measurement = measurement
            self.history = history
        }
    }

    enum InferencePreparer {
        /// Measures the full semantic AgentRequest, including structured tool
        /// definitions and non-text message blocks. This is a lexical estimate
        /// over the JSON representation, NOT a provider-exact token count or
        /// a claim about the adapter's final wire encoding.
        public static func prepare(
            request: AgentRequest,
            frame: Frame,
            delivery: InferenceDelivery,
            maximumInputTokens: Int,
            estimationOptions: TokenEstimationOptions = .agenticContext,
            historyPolicy: HistoryPolicy = .init()
        ) throws -> InferencePreparation {
            guard maximumInputTokens > 0 else {
                throw ContextInferenceError.invalidInputBudget(maximumInputTokens)
            }

            let uniqueOriginal = try uniqueMessages(request.messages)
            let originalSystem = uniqueOriginal.filter { $0.role == .system }
            let systemByID = Dictionary(uniqueKeysWithValues: originalSystem.map { ($0.id, $0) })
            let frameMessages = frame.messages

            let originalByID = Dictionary(uniqueKeysWithValues: uniqueOriginal.map { ($0.id, $0) })
            for message in frameMessages {
                switch message.role {
                case .system:
                    guard systemByID[message.id] == message else {
                        throw ContextInferenceError.foreignSystemMessage(message.id)
                    }
                case .user:
                    guard originalByID[message.id] == message else {
                        throw ContextInferenceError.foreignUserMessage(message.id)
                    }
                case .tool:
                    guard originalByID[message.id] == message else {
                        throw ContextInferenceError.foreignToolMessage(message.id)
                    }
                case .assistant:
                    break
                }
            }

            let assembled: [Message]
            switch delivery {
            case .supplement:
                assembled = try uniqueMessages(uniqueOriginal + frameMessages)

            case .working_set:
                guard let latestUser = uniqueOriginal.lastIndex(where: { $0.role == .user }) else {
                    throw ContextInferenceError.noCurrentUserMessage
                }
                let tail = Array(uniqueOriginal[latestUser...])
                assembled = try uniqueMessages(originalSystem + frameMessages + tail)

            case .dynamic:
                let tail = try selectTail(
                    from: uniqueOriginal,
                    policy: historyPolicy,
                    estimationOptions: estimationOptions
                )
                assembled = try uniqueMessages(originalSystem + frameMessages + tail)
            }

            let counts = try validateToolRelationships(assembled)
            var prepared = request
            prepared.messages = assembled

            let encoded = try JSONEncoder().encode(prepared)
            let estimate = TokenEstimator.estimate(
                String(decoding: encoded, as: UTF8.self),
                options: estimationOptions,
                source: "context.inference_request_json"
            )
            guard estimate.estimatedTokens <= maximumInputTokens else {
                throw ContextInferenceError.inputBudgetExceeded(
                    estimated: estimate.estimatedTokens,
                    maximum: maximumInputTokens
                )
            }

            let measurement = InferenceMeasurement(
                selectedAllocations: frame.items.count,
                skippedAllocations: frame.skippedAllocationIDs.count,
                distinctSources: Set(frame.items.map(\.observed.source)).count,
                messageCount: assembled.count,
                toolDefinitionCount: prepared.tools.count,
                toolCallCount: counts.calls,
                toolResultCount: counts.results,
                serializedRequestBytes: encoded.count,
                estimatedInputTokens: estimate.estimatedTokens,
                maximumInputTokens: maximumInputTokens
            )
            let included = Set(assembled.map(\.id))
            let history = HistorySelection(
                retained: uniqueOriginal.enumerated().compactMap { index, message in
                    included.contains(message.id)
                        ? .init(index: index, messageID: message.id) : nil
                },
                omitted: uniqueOriginal.enumerated().compactMap { index, message in
                    included.contains(message.id)
                        ? nil : .init(index: index, messageID: message.id)
                }
            )
            return InferencePreparation(
                request: prepared,
                frame: frame,
                delivery: delivery,
                measurement: measurement,
                history: history
            )
        }

        /// Select only complete user-originating turns; never cut a tool call
        /// away from its result by evicting individual messages.
        private static func selectTail(
            from messages: [Message],
            policy: HistoryPolicy,
            estimationOptions: TokenEstimationOptions
        ) throws -> [Message] {
            guard policy.maximumTurns > 0, policy.maximumTokens > 0 else {
                throw ContextInferenceError.invalidInputBudget(policy.maximumTokens)
            }
            let userStarts = messages.indices.filter { messages[$0].role == .user }
            guard let latest = userStarts.last else {
                throw ContextInferenceError.noCurrentUserMessage
            }
            let starts = Array(userStarts.suffix(policy.maximumTurns))
            var selected = Array(messages[latest...])
            // Completed tool exchanges can be removed as WHOLE exchanges,
            // including within the newest user turn. The current user
            // instruction and unfinished tool exchanges are never truncated.
            while true {
                let tokens = try estimatedTailTokens(selected, options: estimationOptions)
                guard tokens > policy.maximumTokens else { break }
                guard let exchange = firstCompletedExchange(in: selected) else {
                    throw ContextInferenceError.requiredHistoryExceedsTailBudget(
                        estimated: tokens, maximum: policy.maximumTokens
                    )
                }
                selected.removeSubrange(exchange)
            }
            for start in starts.dropLast().reversed() {
                let candidate = Array(messages[start..<latest]) + selected
                let tokens = try estimatedTailTokens(candidate, options: estimationOptions)
                guard tokens <= policy.maximumTokens else { break }
                selected = candidate
            }
            return selected
        }

        private static func estimatedTailTokens(
            _ messages: [Message],
            options: TokenEstimationOptions
        ) throws -> Int {
            let encoded = try JSONEncoder().encode(messages)
            return TokenEstimator.estimate(
                String(decoding: encoded, as: UTF8.self),
                options: options,
                source: "context.history_tail_json"
            ).estimatedTokens
        }

        private static func firstCompletedExchange(
            in messages: [Message]
        ) -> Range<Int>? {
            for start in messages.indices {
                let assistant = messages[start]
                guard assistant.role == .assistant else { continue }
                let calls = Set(assistant.content.blocks.compactMap { block -> String? in
                    if case .tool_call(let call) = block { return call.id }
                    return nil
                })
                guard !calls.isEmpty else { continue }
                var next = start + 1
                var answered: Set<String> = []
                while next < messages.count, messages[next].role == .tool {
                    let results = Set(messages[next].content.blocks.compactMap { block -> String? in
                        if case .tool_result(let result) = block { return result.call.id }
                        return nil
                    })
                    guard !results.isEmpty, results.isSubset(of: calls) else { break }
                    answered.formUnion(results)
                    next += 1
                }
                if answered == calls { return start..<next }
            }
            return nil
        }

        private static func uniqueMessages(_ messages: [Message]) throws -> [Message] {
            var byID: [String: Message] = [:]
            var result: [Message] = []
            for message in messages {
                if let existing = byID[message.id] {
                    guard existing == message else {
                        throw ContextInferenceError.conflictingMessageID(message.id)
                    }
                    continue
                }
                byID[message.id] = message
                result.append(message)
            }
            return result
        }

        private static func validateToolRelationships(
            _ messages: [Message]
        ) throws -> (calls: Int, results: Int) {
            var calls: Set<String> = []
            var results = 0
            for message in messages {
                for block in message.content.blocks {
                    switch block {
                    case .tool_call(let call):
                        guard calls.insert(call.id).inserted else {
                            throw ContextInferenceError.duplicateToolCall(call.id)
                        }
                    case .tool_result(let result):
                        guard calls.contains(result.call.id) else {
                            throw ContextInferenceError.unpairedToolResult(result.call.id)
                        }
                        results += 1
                    case .text, .resource:
                        break
                    }
                }
            }
            return (calls.count, results)
        }
    }
}
