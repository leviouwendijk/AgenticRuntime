import Agentic
import Foundation

public struct AgentCompactor: Sendable {
    public let strategy: CompactionStrategy

    public init(
        strategy: CompactionStrategy = .default
    ) {
        self.strategy = strategy
    }

    @discardableResult
    public func compact(
        checkpoint: inout AgentHistoryCheckpoint
    ) -> CompactedHistory? {
        let messages = checkpoint.state.messages

        guard strategy.trigger.shouldCompact(
            messages: messages
        ) else {
            return nil
        }

        let preservedPrefixCount = leadingSystemPreservationCount(
            in: messages
        )

        let tailCount = strategy.retention.preserveRecentMessageCount
        let compactableUpperBound = max(
            preservedPrefixCount,
            messages.count - tailCount
        )

        guard compactableUpperBound > preservedPrefixCount else {
            return nil
        }

        let compactable = Array(
            messages[preservedPrefixCount..<compactableUpperBound]
        )

        guard compactable.count >= strategy.trigger.minimumCompactedMessageCount else {
            return nil
        }

        let retainedTail = Array(
            messages[compactableUpperBound..<messages.count]
        )

        let summaryMessage = makeSummaryMessage(
            compacting: compactable,
            iteration: checkpoint.state.iteration
        )

        checkpoint.state.messages =
            Array(messages[..<preservedPrefixCount])
            + [summaryMessage]
            + retainedTail

        return .init(
            summaryMessageID: summaryMessage.id,
            replacedMessageCount: compactable.count,
            retainedMessageCount: checkpoint.state.messages.count,
            estimatedCharactersCompacted: strategy.trigger.approximateCharacterCount(
                in: compactable
            )
        )
    }
}

private extension AgentCompactor {
    func leadingSystemPreservationCount(
        in messages: [AgentMessage]
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
        compacting messages: [AgentMessage],
        iteration: Int
    ) -> AgentMessage {
        let id = "agentic.compaction.\(UUID().uuidString)"

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
        in messages: [AgentMessage]
    ) -> String {
        var counts: [AgentRole: Int] = [:]

        for message in messages {
            counts[message.role, default: 0] += 1
        }

        let orderedRoles: [AgentRole] = [
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
        from messages: [AgentMessage]
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
        for message: AgentMessage
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

            case .tool_call(let value):
                return "tool call \(value.name)"

            case .tool_result(let value):
                if let name = value.name {
                    return value.isError
                        ? "tool result \(name) error"
                        : "tool result \(name)"
                }

                return value.isError
                    ? "tool result \(value.toolCallID) error"
                    : "tool result \(value.toolCallID)"
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
        _ message: AgentMessage
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
