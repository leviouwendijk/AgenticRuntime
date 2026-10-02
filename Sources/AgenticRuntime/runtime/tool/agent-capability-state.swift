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

    public let installedTools: [ToolDescriptor]
    public let availableTools: AgentToolAvailability
    public let visibleTools: AgentToolExposure

    public init(
        installedDefinitions: [ToolDescriptor],
        availableCapabilities: AgentCapabilitySet? = nil,
        visibleToolPolicy: AgentToolExposurePolicy = .all
    ) {
        var seen: Set<ToolIdentifier> = []
        let installedTools = installedDefinitions.filter { definition in
            seen.insert(
                definition.identifier
            ).inserted
        }
        let installedIdentifiers = Set(
            installedTools.map(\.identifier)
        )
        let requestedAvailableIdentifiers =
            availableCapabilities.map { capabilities in
                Set(
                    capabilities.tools
                )
            }
            ?? installedIdentifiers
        let availableIdentifiers =
            requestedAvailableIdentifiers
                .intersection(
                    installedIdentifiers
                )
        let availableTools = AgentToolAvailability(
            definitions: installedTools.filter { definition in
                availableIdentifiers.contains(
                    definition.identifier
                )
            }
        )
        let constrainedVisibility = Self.constrainedVisibility(
            visibleToolPolicy,
            availableIdentifiers: Set(
                availableTools.identifiers
            )
        )

        self.installedTools = installedTools
        self.availableTools = availableTools
        self.visibleTools = AgentToolExposure(
            policy: constrainedVisibility
        )
    }

    public var installedToolIdentifiers: [ToolIdentifier] {
        installedTools.map(
            \.identifier
        )
    }

    @discardableResult
    public func activate(
        _ identifiers: [ToolIdentifier]
    ) async throws -> [ToolIdentifier] {
        try await visibleTools.activate(
            identifiers.filter(
                availableTools.contains
            )
        )
    }

    @discardableResult
    public func restoreVisibleToolIdentifiers(
        _ identifiers: [ToolIdentifier],
        in registry: ToolRegistry
    ) async throws -> [ToolIdentifier] {
        try await visibleTools.activate(
            identifiers.filter(
                availableTools.contains
            ),
            in: registry
        )
    }

    public func snapshot(
        in registry: ToolRegistry
    ) async throws -> Snapshot {
        .init(
            installed: installedToolIdentifiers,
            available: availableTools.identifiers,
            visible: try await visibleTools.identifiers(
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
