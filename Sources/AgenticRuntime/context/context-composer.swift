import AgenticWorkspace
import Concatenation
import Foundation
import Path
import PathParsing
import Selection
import SelectionParsing

public struct ContextComposer: Sendable {
    public let workspace: AgentWorkspace?

    public init(
        workspace: AgentWorkspace? = nil
    ) {
        self.workspace = workspace
    }

    public func compose(
        _ plan: ContextCompositionPlan
    ) throws -> ComposedContext {
        var sections: [String] = []
        var appendedFileContext = false

        for source in plan.sources {
            switch source {
            case .text(let value):
                let trimmed = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !trimmed.isEmpty {
                    sections.append(trimmed)
                }

            case .message(let message):
                let text = message.content.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !text.isEmpty {
                    sections.append(text)
                }

            case .transcriptEvent(let event):
                let text = event.summaryText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !text.isEmpty {
                    sections.append(text)
                }

            case .files(let fileSource):
                let rendered = try composeFileSource(
                    fileSource,
                    metadata: plan.metadata
                )

                if !rendered.isEmpty {
                    sections.append(rendered)
                    appendedFileContext = true
                }

            case .skill(let skill):
                let text = skill.contextText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !text.isEmpty {
                    sections.append(text)
                }
            }
        }

        if appendedFileContext,
           let concatenationContext = concatenationContext(
                from: plan.metadata
           ) {
            let syntheticOutputURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "agentic-context-\(UUID().uuidString).txt"
                )

            sections.insert(
                concatenationContext.header(
                    outputURL: syntheticOutputURL
                ),
                at: 0
            )
        }

        return ComposedContext(
            metadata: plan.metadata,
            text: sections.joined(separator: "\n\n")
        )
    }
}

private extension ContextComposer {
    static let toolName = "context_composer"

    enum ContextComposerError: Error, LocalizedError {
        case workspaceRequired

        var errorDescription: String? {
            switch self {
            case .workspaceRequired:
                return "ContextComposer requires an AgentWorkspace for file-backed context sources."
            }
        }
    }

    func composeFileSource(
        _ source: ContextFileSource,
        metadata: ContextMetadata
    ) throws -> String {
        guard let workspace else {
            throw ContextComposerError.workspaceRequired
        }

        let root = try workspace.accessController.root(
            id: source.rootID
        )

        _ = try workspace.accessController.authorize(
            rootID: source.rootID,
            path: ".",
            capability: .scan,
            toolName: Self.toolName,
            type: .directory
        )

        let includes = try normalizedExpressions(
            source.includes
        ).map {
            try PathParse.expression($0)
        }

        let excludes = try normalizedExpressions(
            source.excludes
        ).map {
            try PathParse.expression($0)
        }

        let selections = try normalizedExpressions(
            source.selections
        ).map {
            try PathSelectionExpressionParser.parse($0)
        }

        guard !includes.isEmpty || !selections.isEmpty else {
            return ""
        }

        let specification = SelectionScanSpecification(
            includes: includes,
            excludes: excludes,
            selections: selections
        )

        let result = try SelectionScan.scan(
            specification,
            relativeTo: .directoryURL(root.rootURL),
            configuration: .init(
                maxDepth: source.recursive ? nil : 1,
                includeHidden: source.includeHidden,
                followSymlinks: source.followSymlinks,
                emitDirectories: false,
                emitFiles: true
            )
        )

        let allowedMatches: [(url: URL, contentSelections: [ContentSelection])] = result.matches.compactMap { match in
            guard let authorized = try? workspace.accessController.authorize(
                rootID: source.rootID,
                url: match.url,
                capability: .read,
                toolName: Self.toolName,
                type: .file
            ) else {
                return nil
            }

            return (
                url: authorized.absoluteURL,
                contentSelections: match.contentSelections
            )
        }

        guard !allowedMatches.isEmpty else {
            return ""
        }

        let syntheticOutputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "agentic-context-\(UUID().uuidString).txt"
            )

        let concatenator = FileConcatenator(
            inputFiles: allowedMatches.map(\.url),
            outputURL: syntheticOutputURL,
            context: nil,
            selectedContentByFile: selectedContentByFile(
                from: allowedMatches
            ),
            delimiterStyle: source.delimiterStyle,
            delimiterClosure: false,
            maxLinesPerFile: source.maxLinesPerFile,
            trimBlankLines: true,
            relativePaths: true,
            rawOutput: false,
            includeSourceLineNumbers: source.includeSourceLineNumbers,
            includeSourceModifiedAt: false,
            obscureMap: [:],
            copyToClipboard: false,
            verbose: false,
            location: metadata.title,
            protectSecrets: true,
            allowSecrets: false,
            failOnBlockedFiles: false,
            deepSecretInspection: false
        )

        return try concatenator.render().text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        )
    }

    func concatenationContext(
        from metadata: ContextMetadata
    ) -> ConcatenationContext? {
        let dependencies = metadata.attributes.isEmpty
            ? nil
            : metadata.attributes
                .map { key, value in
                    "\(key)=\(value)"
                }
                .sorted()

        guard metadata.title != nil
            || metadata.details != nil
            || dependencies != nil
        else {
            return nil
        }

        return .init(
            title: metadata.title,
            details: metadata.details,
            dependencies: dependencies,
            concatenatedFile: nil
        )
    }

    func normalizedExpressions(
        _ values: [String]
    ) -> [String] {
        values.map {
            $0.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }.filter {
            !$0.isEmpty
        }
    }

    func selectedContentByFile(
        from matches: [(url: URL, contentSelections: [ContentSelection])]
    ) -> [URL: [ContentSelection]] {
        matches.reduce(
            into: [URL: [ContentSelection]]()
        ) { partial, match in
            guard !match.contentSelections.isEmpty else {
                return
            }

            partial[match.url.standardizedFileURL] = match.contentSelections
        }
    }
}
