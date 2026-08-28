import AgenticWorkspace
import Concatenation
import Path

public struct ContextFileSource: Sendable, Codable, Hashable {
    public var rootID: PathAccessRootIdentifier
    public var includes: [String]
    public var excludes: [String]
    public var selections: [String]
    public var recursive: Bool
    public var includeHidden: Bool
    public var followSymlinks: Bool
    public var delimiterStyle: DelimiterStyle
    public var includeSourceLineNumbers: Bool
    public var maxLinesPerFile: Int?

    public init(
        rootID: PathAccessRootIdentifier = .project,
        includes: [String] = [],
        excludes: [String] = [],
        selections: [String] = [],
        recursive: Bool = true,
        includeHidden: Bool = false,
        followSymlinks: Bool = false,
        delimiterStyle: DelimiterStyle = .boxed,
        includeSourceLineNumbers: Bool = false,
        maxLinesPerFile: Int? = 10_000
    ) {
        self.rootID = rootID
        self.includes = includes
        self.excludes = excludes
        self.selections = selections
        self.recursive = recursive
        self.includeHidden = includeHidden
        self.followSymlinks = followSymlinks
        self.delimiterStyle = delimiterStyle
        self.includeSourceLineNumbers = includeSourceLineNumbers
        self.maxLinesPerFile = maxLinesPerFile
    }
}

private extension ContextFileSource {
    enum CodingKeys: String, CodingKey {
        case rootID
        case includes
        case excludes
        case selections
        case recursive
        case includeHidden
        case followSymlinks
        case delimiterStyle
        case includeSourceLineNumbers
        case maxLinesPerFile
    }
}

public extension ContextFileSource {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            rootID: try container.decodeIfPresent(
                PathAccessRootIdentifier.self,
                forKey: .rootID
            ) ?? .project,
            includes: try container.decodeIfPresent(
                [String].self,
                forKey: .includes
            ) ?? [],
            excludes: try container.decodeIfPresent(
                [String].self,
                forKey: .excludes
            ) ?? [],
            selections: try container.decodeIfPresent(
                [String].self,
                forKey: .selections
            ) ?? [],
            recursive: try container.decodeIfPresent(
                Bool.self,
                forKey: .recursive
            ) ?? true,
            includeHidden: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeHidden
            ) ?? false,
            followSymlinks: try container.decodeIfPresent(
                Bool.self,
                forKey: .followSymlinks
            ) ?? false,
            delimiterStyle: try container.decodeIfPresent(
                DelimiterStyle.self,
                forKey: .delimiterStyle
            ) ?? .boxed,
            includeSourceLineNumbers: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeSourceLineNumbers
            ) ?? false,
            maxLinesPerFile: try container.decodeIfPresent(
                Int.self,
                forKey: .maxLinesPerFile
            ) ?? 10_000
        )
    }
}
