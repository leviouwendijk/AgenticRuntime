import Agentic

/// Runtime authority derived from one installed Agent definition.
///
/// Authored availability and visibility are resolved independently, then bounded
/// by the executable Runtime universe so that:
///
/// visible ⊆ available ⊆ installed
public struct AgentRealization:
    Sendable
{
    public let definition: AgentDefinition
    public let requestedAvailable: AgentCapabilitySet
    public let requestedVisible: AgentCapabilitySet
    public let installed: AgentCapabilitySet
    public let available: AgentCapabilitySet
    public let visible: AgentCapabilitySet

    init(
        definition: AgentDefinition,
        requestedAvailable: AgentCapabilitySet,
        requestedVisible: AgentCapabilitySet,
        installed: AgentCapabilitySet,
        available: AgentCapabilitySet,
        visible: AgentCapabilitySet
    ) {
        self.definition = definition
        self.requestedAvailable = requestedAvailable
        self.requestedVisible = requestedVisible
        self.installed = installed
        self.available = available
        self.visible = visible
    }

    public var identifier: AgentIdentifier {
        definition.identifier
    }

    public var instructions: String? {
        definition.instructions
    }

    public var modelSelection: AgentModelSelection {
        definition.modelSelection
    }

    public var delegation: AgentDelegationPolicy {
        definition.delegation
    }

    public func makeCapabilityState() -> AgentCapabilityState {
        AgentCapabilityState(
            installed: installed,
            available: available,
            visible: visible
        )
    }

}

extension AgentRealization {
    static func materialize(
        definition: AgentDefinition,
        installed: InstalledCapabilities
    ) -> Self {
        let requestedAvailable = installed.catalog.resolve(
            definition.capabilities.available
        )
        let requestedVisible = installed.catalog.resolve(
            definition.capabilities.visible
        )
        let available = requestedAvailable.intersecting(installed.capabilities)
        let visible = requestedVisible.intersecting(available)
        return .init(
            definition: definition,
            requestedAvailable: requestedAvailable,
            requestedVisible: requestedVisible,
            installed: installed.capabilities,
            available: available,
            visible: visible
        )
    }
}

