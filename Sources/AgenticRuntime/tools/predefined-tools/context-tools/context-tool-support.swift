import Foundation

public struct ContextSizeEstimate: Sendable, Codable, Hashable {
    public let characterCount: Int
    public let byteCount: Int
    public let lineCount: Int
    public let approximateTokenCount: Int

    public init(
        characterCount: Int,
        byteCount: Int,
        lineCount: Int,
        approximateTokenCount: Int
    ) {
        self.characterCount = characterCount
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.approximateTokenCount = approximateTokenCount
    }
}

public struct ContextSourceInspection: Sendable, Codable, Hashable {
    public let index: Int
    public let kind: String
    public let summary: String
    public let estimatedCharacterCount: Int?
    public let approximateTokenCount: Int?

    public init(
        index: Int,
        kind: String,
        summary: String,
        estimatedCharacterCount: Int?,
        approximateTokenCount: Int?
    ) {
        self.index = index
        self.kind = kind
        self.summary = summary
        self.estimatedCharacterCount = estimatedCharacterCount
        self.approximateTokenCount = approximateTokenCount
    }
}

public struct ContextPlanInspection: Sendable, Codable, Hashable {
    public let sourceCount: Int
    public let sources: [ContextSourceInspection]
    public let knownCharacterCount: Int
    public let knownApproximateTokenCount: Int
    public let hasFileBackedSources: Bool
    public let hasUnknownSizeSources: Bool

    public init(
        sourceCount: Int,
        sources: [ContextSourceInspection],
        knownCharacterCount: Int,
        knownApproximateTokenCount: Int,
        hasFileBackedSources: Bool,
        hasUnknownSizeSources: Bool
    ) {
        self.sourceCount = sourceCount
        self.sources = sources
        self.knownCharacterCount = knownCharacterCount
        self.knownApproximateTokenCount = knownApproximateTokenCount
        self.hasFileBackedSources = hasFileBackedSources
        self.hasUnknownSizeSources = hasUnknownSizeSources
    }
}

enum ContextToolSupport {
    static func inspect(
        _ plan: ContextCompositionPlan
    ) -> ContextPlanInspection {
        let sources = plan.sources.enumerated().map { index, source in
            inspect(
                source,
                index: index
            )
        }

        let knownCharacterCount = sources.reduce(0) { partial, source in
            partial + (source.estimatedCharacterCount ?? 0)
        }

        let knownApproximateTokenCount = sources.reduce(0) { partial, source in
            partial + (source.approximateTokenCount ?? 0)
        }

        let hasFileBackedSources = plan.sources.contains { source in
            guard case .files = source else {
                return false
            }

            return true
        }

        let hasUnknownSizeSources = sources.contains { source in
            source.estimatedCharacterCount == nil
        }

        return .init(
            sourceCount: sources.count,
            sources: sources,
            knownCharacterCount: knownCharacterCount,
            knownApproximateTokenCount: knownApproximateTokenCount,
            hasFileBackedSources: hasFileBackedSources,
            hasUnknownSizeSources: hasUnknownSizeSources
        )
    }

    static func estimate(
        text: String
    ) -> ContextSizeEstimate {
        .init(
            characterCount: text.count,
            byteCount: text.utf8.count,
            lineCount: lineCount(
                in: text
            ),
            approximateTokenCount: approximateTokenCount(
                forCharacterCount: text.count
            )
        )
    }

    static func approximateTokenCount(
        forCharacterCount characterCount: Int
    ) -> Int {
        guard characterCount > 0 else {
            return 0
        }

        return max(
            1,
            (characterCount + 3) / 4
        )
    }

    static func truncated(
        _ text: String,
        maxCharacters: Int?
    ) -> (text: String, truncated: Bool) {
        guard let maxCharacters else {
            return (
                text,
                false
            )
        }

        let clamped = max(
            0,
            maxCharacters
        )

        guard text.count > clamped else {
            return (
                text,
                false
            )
        }

        return (
            String(
                text.prefix(
                    clamped
                )
            ),
            true
        )
    }
}

private extension ContextToolSupport {
    static func inspect(
        _ source: ContextSource,
        index: Int
    ) -> ContextSourceInspection {
        switch source {
        case .text(let value):
            return inspection(
                index: index,
                kind: "text",
                summary: preview(
                    value
                ),
                text: value
            )

        case .message(let message):
            let text = message.content.text

            return inspection(
                index: index,
                kind: "message",
                summary: preview(
                    text
                ),
                text: text
            )

        case .transcriptEvent(let event):
            let text = event.summaryText

            return inspection(
                index: index,
                kind: "transcript_event",
                summary: preview(
                    text
                ),
                text: text
            )

        case .files(let fileSource):
            let summary = [
                "includes=\(fileSource.includes.count)",
                "excludes=\(fileSource.excludes.count)",
                "selections=\(fileSource.selections.count)",
                "recursive=\(fileSource.recursive)",
                "lineNumbers=\(fileSource.includeSourceLineNumbers)"
            ].joined(separator: ", ")

            return .init(
                index: index,
                kind: "files",
                summary: summary,
                estimatedCharacterCount: nil,
                approximateTokenCount: nil
            )

        case .skill(let skill):
            let text = skill.contextText

            return inspection(
                index: index,
                kind: "skill",
                summary: skill.name,
                text: text
            )
        }
    }

    static func inspection(
        index: Int,
        kind: String,
        summary: String,
        text: String
    ) -> ContextSourceInspection {
        let characterCount = text.count

        return .init(
            index: index,
            kind: kind,
            summary: summary,
            estimatedCharacterCount: characterCount,
            approximateTokenCount: approximateTokenCount(
                forCharacterCount: characterCount
            )
        )
    }

    static func preview(
        _ value: String,
        limit: Int = 120
    ) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard trimmed.count > limit else {
            return trimmed
        }

        return String(
            trimmed.prefix(
                limit
            )
        )
    }

    static func lineCount(
        in text: String
    ) -> Int {
        guard !text.isEmpty else {
            return 0
        }

        return text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }
}
