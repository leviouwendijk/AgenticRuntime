import Agentic
import AgenticExecution
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

    public let toolRegistrations: [AgentToolRegistration]
    public let skillRegistrations: [AgentSkillRegistration]
    public let programRegistrations: [AgentRuntimeProgramRegistration]
    public let gatewayFactories: [AgentModelGatewayFactory]
    public let modelProviders: [any AgentModelProvider]

    public init(
        identifier: AgenticApplicationIdentifier,
        title: String? = nil,
        metadata: [String: String] = [:],
        components: [AgenticApplicationComponent] = []
    ) {
        var toolRegistrations: [AgentToolRegistration] = []
        var skillRegistrations: [AgentSkillRegistration] = []
        var programRegistrations: [AgentRuntimeProgramRegistration] = []
        var gatewayFactories: [AgentModelGatewayFactory] = []
        var modelProviders: [any AgentModelProvider] = []

        for component in components {
            switch component {
            case .tools(let registrations):
                toolRegistrations.append(
                    contentsOf: registrations
                )

            case .skills(let registrations):
                skillRegistrations.append(
                    contentsOf: registrations
                )

            case .programs(let registrations):
                programRegistrations.append(
                    contentsOf: registrations
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
        self.toolRegistrations = toolRegistrations
        self.skillRegistrations = skillRegistrations
        self.programRegistrations = programRegistrations
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
