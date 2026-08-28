import Agentic

public extension ModeCatalog {
    static var standard: Self {
        get throws {
            try .init(
                modes: [
                    .planning,
                    .research,
                    .coder,
                    .review,
                    .debugging,
                    .cheap_utility,
                    .private
                ]
            )
        }
    }
}

public extension Agentic {
    struct ModeAPI: Sendable {
        public init() {}

        public func catalog() throws -> ModeCatalog {
            try .standard
        }

        public func selection(
            _ id: AgenticModeIdentifier,
            overlay: ModeOverlay = .init()
        ) throws -> ModeSelection {
            try catalog().selection(
                id,
                overlay: overlay
            )
        }
    }

    static let mode: ModeAPI = .init()
}
