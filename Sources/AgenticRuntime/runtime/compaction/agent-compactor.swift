import Agentic
import Foundation

public struct AgentCompactor: Sendable {
    public let strategy: CompactionStrategy

    public init(
        strategy: CompactionStrategy = .default
    ) {
        self.strategy = strategy
    }

    /// Only the request projection is compacted. Checkpoint history is canonical.
    /// Source messages remain accessible in their original order and with IDs.
    public func project(
        messages: [Message],
        iteration: Int
    ) -> Projection? {
        guard strategy.trigger.shouldCompact(messages: messages) else {
            return nil
        }
        let prefix = leadingSystemPreservationCount(in: messages)
        let upperBound = max(prefix, messages.count - strategy.retention.preserveRecentMessageCount)
        guard upperBound > prefix else { return nil }

        // Cut at a user-turn boundary, never inside a tool exchange.
        guard let boundary = (prefix...upperBound).reversed().first(where: {
            $0 < messages.count && messages[$0].role == .user
        }), boundary > prefix else { return nil }
        let compactable = Array(messages[prefix..<boundary])
        guard compactable.count >= strategy.trigger.minimumCompactedMessageCount else {
            return nil
        }
        let summary = makeSummaryMessage(compacting: compactable, iteration: iteration)
        let projected = Array(messages[..<prefix]) + [summary] + Array(messages[boundary...])
        let report = CompactedHistory(
            summaryMessageID: summary.id,
            replacedMessageCount: compactable.count,
            retainedMessageCount: projected.count,
            estimatedCharactersCompacted: strategy.trigger.approximateCharacterCount(in: compactable)
        )
        return Projection(messages: projected, history: report)
    }

    public struct Projection: Sendable {
        public let messages: [Message]
        public let history: CompactedHistory
    }

    /// Compatibility entry point: reports a projected compaction but does
    /// NOT mutate checkpoint.state.messages.
    public func compact(checkpoint: AgentRunner.Checkpoint) -> CompactedHistory? {
        project(messages: checkpoint.state.messages, iteration: checkpoint.state.iteration)?.history
    }
}

private extension AgentCompactor {
    func leadingSystemPreservationCount(
        in messages: [Message]
    ) -> Int {
        guard strategy.retention.preserveLeadingSystemMessages else {
            return 0
        }

        var count = 0

        for message in messages {
            guard message.role == .system else {
                break
            }

            guard !isCompactionMessage(
                message
            ) else {
                break
            }

            count += 1
        }

        return count
    }

    func makeSummaryMessage(
        compacting messages: [Message],
        iteration: Int
    ) -> Message {
        let id = "agentic.compaction.\(iteration).\(messages.count)"

        var lines: [String] = [
            "[agentic.compaction]",
            "Compacted \(messages.count) earlier message(s) before iteration \(iteration).",
            "Recent messages remain verbatim below.",
            ""
        ]

        let roleSummary = roleBreakdown(
            in: messages
        )

        if !roleSummary.isEmpty {
            lines.append(
                "Role counts: \(roleSummary)"
            )
            lines.append("")
        }

        lines.append("Excerpts:")

        for excerpt in excerpts(
            from: messages
        ) {
            lines.append("- \(excerpt)")
        }

        return .init(
            id: id,
            role: .system,
            content: .init(
                text: lines.joined(separator: "\n")
            )
        )
    }

    func roleBreakdown(
        in messages: [Message]
    ) -> String {
        var counts: [MessageRole: Int] = [:]

        for message in messages {
            counts[message.role, default: 0] += 1
        }

        let orderedRoles: [MessageRole] = [
            .system,
            .user,
            .assistant,
            .tool
        ]

        return orderedRoles.compactMap { role in
            guard let count = counts[role] else {
                return nil
            }

            return "\(role.rawValue)=\(count)"
        }.joined(separator: ", ")
    }

    func excerpts(
        from messages: [Message]
    ) -> [String] {
        if messages.count <= strategy.maxExcerptCount {
            return messages.map(
                excerpt(for:)
            )
        }

        let headCount = max(
            1,
            strategy.maxExcerptCount / 2
        )
        let tailCount = max(
            1,
            strategy.maxExcerptCount - headCount
        )

        let head = messages.prefix(headCount)
        let tail = messages.suffix(tailCount)
        let omitted = max(
            0,
            messages.count - head.count - tail.count
        )

        var rendered = head.map(
            excerpt(for:)
        )

        if omitted > 0 {
            rendered.append(
                "... \(omitted) message(s) omitted ..."
            )
        }

        rendered.append(
            contentsOf: tail.map(
                excerpt(for:)
            )
        )

        return rendered
    }

    func excerpt(
        for message: Message
    ) -> String {
        if isCompactionMessage(
            message
        ) {
            return "system: prior compaction summary"
        }

        let parts = message.content.blocks.compactMap { block -> String? in
            switch block {
            case .text(let value):
                let normalized = normalizeWhitespace(
                    in: value
                )

                guard !normalized.isEmpty else {
                    return nil
                }

                return normalized

            case .resource(let value):
                let label = value.metadata.title
                    ?? value.metadata.filename
                    ?? value.contentType

                if let label {
                    return "resource \(value.modality.rawValue) \(label)"
                }

                return "resource \(value.modality.rawValue)"

            case .tool_call(let value):
                return "tool call \(value.tool.rawValue)"

            case .tool_result(let value):
                let name = value.call.tool.rawValue
                return value.isError
                    ? "tool result \(name) error"
                    : "tool result \(name)"
            }
        }

        let body = parts.isEmpty
            ? "(empty)"
            : parts.joined(separator: " | ")

        return "\(message.role.rawValue): \(truncate(body))"
    }

    func normalizeWhitespace(
        in value: String
    ) -> String {
        value.split(
            whereSeparator: \.isWhitespace
        ).joined(separator: " ")
    }

    func truncate(
        _ value: String
    ) -> String {
        guard value.count > strategy.maxExcerptLength else {
            return value
        }

        let index = value.index(
            value.startIndex,
            offsetBy: strategy.maxExcerptLength
        )
        return "\(value[..<index])…"
    }

    func isCompactionMessage(
        _ message: Message
    ) -> Bool {
        if message.id.hasPrefix(
            "agentic.compaction."
        ) {
            return true
        }

        guard message.role == .system else {
            return false
        }

        let normalized = normalizeWhitespace(
            in: message.content.text
        )

        return normalized.hasPrefix(
            "[agentic.compaction]"
        )
    }
}
