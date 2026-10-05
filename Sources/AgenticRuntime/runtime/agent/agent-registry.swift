import Agentic
import Foundation

public enum AgentRegistryError:
    Error,
    Sendable,
    LocalizedError
{
    case duplicateAgent(
        AgentIdentifier
    )
    case unknownAgent(
        AgentIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .duplicateAgent(let identifier):
            return "An Agent with id '\(identifier.rawValue)' is already installed."

        case .unknownAgent(let identifier):
            return "Unknown Agent: \(identifier.rawValue)"
        }
    }
}

public struct AgentRegistry:
    Sendable
{
    private let definitionsByIdentifier:
        [AgentIdentifier: AgentDefinition]

    public init(
        _ definitions: [AgentDefinition] = []
    ) throws {
        var definitionsByIdentifier:
            [AgentIdentifier: AgentDefinition] = [:]

        definitionsByIdentifier.reserveCapacity(
            definitions.count
        )

        for definition in definitions {
            guard definitionsByIdentifier[
                definition.identifier
            ] == nil else {
                throw AgentRegistryError
                    .duplicateAgent(
                        definition.identifier
                    )
            }

            definitionsByIdentifier[
                definition.identifier
            ] = definition
        }

        self.definitionsByIdentifier =
            definitionsByIdentifier
    }

    public var definitions: [AgentDefinition] {
        definitionsByIdentifier.values
            .sorted { lhs, rhs in
                lhs.identifier.rawValue
                    < rhs.identifier.rawValue
            }
    }

    public func definition(
        identifiedBy identifier: AgentIdentifier
    ) -> AgentDefinition? {
        definitionsByIdentifier[
            identifier
        ]
    }

    public func requireAgent(
        identifiedBy identifier: AgentIdentifier
    ) throws -> AgentDefinition {
        guard let definition = definition(
            identifiedBy: identifier
        ) else {
            throw AgentRegistryError
                .unknownAgent(
                    identifier
                )
        }

        return definition
    }
}
