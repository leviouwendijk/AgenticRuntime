import Agentic
import Primitives

public struct AgenticApplicationIdentifier:
    StringIdentifier
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }
}

public struct AgenticApplication:
    Sendable,
    Identifiable
{
    public let identifier: AgenticApplicationIdentifier
    public let title: String
    public let metadata: [String: String]

    public let catalog: Catalog
    public let toolRegistrations: [AgentToolRegistration]
    public let programBindings: [ProgramExecutionBinding]
    public let inferenceBindings: [InferenceBinding]
    public let adapterRegistrations: [any InferenceAdapter]
    public let agentBindings: [AgentBinding]

    /// Compatibility view for consumers that inspect authored definitions.
    /// Does not own a second set of installed Agents.
    public var agentDefinitions: [AgentDefinition] {
        agentBindings.map(\.definition)
    }
    public let launchEntries: [ApplicationLaunchEntry]
    public let gatewayFactories: [AgentModelGatewayFactory]
    public let modelProviders: [any AgentModelProvider]

    public init(
        identifier: AgenticApplicationIdentifier,
        title: String? = nil,
        metadata: [String: String] = [:],
        components: [AgenticApplicationComponent] = []
    ) {
        var catalog = Catalog.none
        var toolRegistrations: [AgentToolRegistration] = []
        var programBindings: [ProgramExecutionBinding] = []
        var inferenceBindings: [InferenceBinding] = []
        var adapterRegistrations: [any InferenceAdapter] = []
        var agentBindings: [AgentBinding] = []
        var launchEntries: [ApplicationLaunchEntry] = []
        var gatewayFactories: [AgentModelGatewayFactory] = []
        var modelProviders: [any AgentModelProvider] = []

        for component in components {
            switch component {
            case .catalog(let contribution):
                catalog = catalog + contribution

            case .tools(let registrations):
                toolRegistrations.append(
                    contentsOf: registrations
                )

            case .programs(let registrations):
                programBindings.append(
                    contentsOf: registrations
                )

            case .inferences(let registrations):
                inferenceBindings.append(
                    contentsOf: registrations
                )

            case .adapters(let registrations):
                adapterRegistrations.append(contentsOf: registrations)

            case .agents(let bindings):
                agentBindings.append(contentsOf: bindings)

            case .launches(let entries):
                launchEntries.append(
                    contentsOf: entries
                )

            case .gateways(let registrations):
                gatewayFactories.append(
                    contentsOf: registrations
                )

            case .modelProviders(let providers):
                modelProviders.append(
                    contentsOf: providers
                )
            }
        }

        self.identifier = identifier
        self.title = title ?? identifier.rawValue
        self.metadata = metadata
        self.catalog = catalog
        self.toolRegistrations = toolRegistrations
        self.programBindings = programBindings
        self.inferenceBindings = inferenceBindings
        self.adapterRegistrations = adapterRegistrations
        self.agentBindings = agentBindings
        self.launchEntries = launchEntries
        self.gatewayFactories = gatewayFactories
        self.modelProviders = modelProviders
    }

    public init(
        identifier: AgenticApplicationIdentifier,
        title: String? = nil,
        metadata: [String: String] = [:],
        @AgenticApplicationBuilder
        _ content: () throws -> [AgenticApplicationComponent]
    ) rethrows {
        self.init(
            identifier: identifier,
            title: title,
            metadata: metadata,
            components: try content()
        )
    }

    public var id: AgenticApplicationIdentifier {
        identifier
    }
}

public extension Agentic {
    static func application(
        _ identifier: AgenticApplicationIdentifier,
        title: String? = nil,
        metadata: [String: String] = [:],
        @AgenticApplicationBuilder
        _ content: () throws -> [AgenticApplicationComponent]
    ) rethrows -> AgenticApplication {
        try AgenticApplication(
            identifier: identifier,
            title: title,
            metadata: metadata,
            components: content()
        )
    }
}
