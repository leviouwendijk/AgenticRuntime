import Agentic

public struct AgentToolAvailability:
    Sendable,
    ToolAvailability
{
    public let modelFacingDefinitions: [ToolDescriptor]
    public let identifiers: [ToolIdentifier]

    private let identifierSet: Set<ToolIdentifier>

    public init(
        definitions: [ToolDescriptor]
    ) {
        var seen: Set<ToolIdentifier> = []
        var definitions = definitions.filter { definition in
            seen.insert(
                definition.identifier
            ).inserted
        }

        definitions.sort { lhs, rhs in
            lhs.name < rhs.name
        }

        self.modelFacingDefinitions = definitions
        self.identifiers = definitions.map(
            \.identifier
        )
        self.identifierSet = Set(
            identifiers
        )
    }

    public func contains(
        _ identifier: ToolIdentifier
    ) -> Bool {
        identifierSet.contains(
            identifier
        )
    }
}

public struct AgentCapabilityState:
    Sendable,
    ToolExposure
{
    public struct Snapshot:
        Sendable,
        Hashable
    {
        public let installed: [ToolIdentifier]
        public let available: [ToolIdentifier]
        public let visible: [ToolIdentifier]

        public init(
            installed: [ToolIdentifier],
            available: [ToolIdentifier],
            visible: [ToolIdentifier]
        ) {
            self.installed = installed
            self.available = available
            self.visible = visible
        }
    }

    public let installed: [ToolDescriptor]
    public let available: AgentToolAvailability
    public let visible: AgentToolExposure

    public init(
        installed: [ToolDescriptor],
        capabilities: AgentCapabilitySet? = nil,
        visibility: AgentToolExposurePolicy = .all
    ) {
        var seen: Set<ToolIdentifier> = []
        let installed = installed.filter { definition in
            seen.insert(
                definition.identifier
            ).inserted
        }
        let installedIDs = Set(
            installed.map(\.identifier)
        )
        let requested =
            capabilities.map { capabilities in
                Set(
                    capabilities.tools
                )
            }
            ?? installedIDs
        let availableIDs = requested.intersection(
            installedIDs
        )
        let available = AgentToolAvailability(
            definitions: installed.filter { definition in
                availableIDs.contains(
                    definition.identifier
                )
            }
        )
        let visibility = Self.constrainedVisibility(
            visibility,
            availableIdentifiers: Set(
                available.identifiers
            )
        )

        self.installed = installed
        self.available = available
        self.visible = AgentToolExposure(
            policy: visibility
        )
    }

    public var installedToolIdentifiers: [ToolIdentifier] {
        installed.map(
            \.identifier
        )
    }

    @discardableResult
    public func activate(
        _ identifiers: [ToolIdentifier]
    ) async throws -> [ToolIdentifier] {
        try await visible.activate(
            identifiers.filter(
                available.contains
            )
        )
    }

    @discardableResult
    public func restoreVisibleToolIdentifiers(
        _ identifiers: [ToolIdentifier],
        in registry: ToolRegistry
    ) async throws -> [ToolIdentifier] {
        try await visible.activate(
            identifiers.filter(
                available.contains
            ),
            in: registry
        )
    }

    public func snapshot(
        in registry: ToolRegistry
    ) async throws -> Snapshot {
        .init(
            installed: installedToolIdentifiers,
            available: available.identifiers,
            visible: try await visible.identifiers(
                in: registry
            )
        )
    }
}

private extension AgentCapabilityState {
    static func constrainedVisibility(
        _ policy: AgentToolExposurePolicy,
        availableIdentifiers: Set<ToolIdentifier>
    ) -> AgentToolExposurePolicy {
        switch policy {
        case .all:
            return .explicit(
                availableIdentifiers.sorted { lhs, rhs in
                    lhs.rawValue < rhs.rawValue
                }
            )

        case .explicit(let identifiers):
            return .explicit(
                filteredVisibleIdentifiers(
                    identifiers,
                    availableIdentifiers: availableIdentifiers
                )
            )

        case .discoverable(let identifiers):
            return .discoverable(
                filteredVisibleIdentifiers(
                    identifiers,
                    availableIdentifiers: availableIdentifiers
                )
            )
        }
    }

    static func filteredVisibleIdentifiers(
        _ identifiers: [ToolIdentifier],
        availableIdentifiers: Set<ToolIdentifier>
    ) -> [ToolIdentifier] {
        var seen: Set<ToolIdentifier> = []

        return identifiers.filter { identifier in
            availableIdentifiers.contains(identifier)
                && seen.insert(identifier).inserted
        }
    }
}
