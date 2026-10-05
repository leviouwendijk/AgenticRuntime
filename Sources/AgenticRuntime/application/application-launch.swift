import Agentic
import Foundation
import Primitives

public struct ApplicationLaunchIdentifier:
    StringIdentifier
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }
}

public enum ApplicationLaunch:
    Sendable,
    Codable,
    Hashable
{
    case agent(AgentIdentifier)
    case program(ProgramIdentifier)
}

public struct ApplicationLaunchEntry:
    Sendable,
    Codable,
    Hashable,
    Identifiable
{
    public let identifier: ApplicationLaunchIdentifier
    public let title: String?
    public let subtitle: String?
    public let launch: ApplicationLaunch

    public init(
        identifier: ApplicationLaunchIdentifier,
        title: String? = nil,
        subtitle: String? = nil,
        launch: ApplicationLaunch
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.launch = launch
    }

    public var id: ApplicationLaunchIdentifier {
        identifier
    }
}

public enum ApplicationLaunchResolutionError:
    Error,
    Sendable,
    LocalizedError
{
    case duplicateIdentifier(
        ApplicationLaunchIdentifier
    )
    case agentNotInstalled(
        AgentIdentifier
    )
    case programNotInstalled(
        ProgramIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .duplicateIdentifier(let identifier):
            return "Application launch identifier '\(identifier.rawValue)' is declared more than once."

        case .agentNotInstalled(let identifier):
            return "Application launch references Agent '\(identifier.rawValue)', but that Agent is not installed."

        case .programNotInstalled(let identifier):
            return "Application launch references Program '\(identifier.rawValue)', but that Program is not installed."
        }
    }
}

func validateApplicationLaunchEntries(
    _ entries: [ApplicationLaunchEntry],
    agents: AgentRegistry,
    programs: ProgramRegistry
) throws -> [ApplicationLaunchEntry] {
    var identifiers: Set<ApplicationLaunchIdentifier> = []

    for entry in entries {
        guard identifiers.insert(
            entry.identifier
        ).inserted else {
            throw ApplicationLaunchResolutionError
                .duplicateIdentifier(
                    entry.identifier
                )
        }

        switch entry.launch {
        case .agent(let identifier):
            guard agents.definition(
                identifiedBy: identifier
            ) != nil else {
                throw ApplicationLaunchResolutionError
                    .agentNotInstalled(
                        identifier
                    )
            }

        case .program(let identifier):
            guard programs.registeredProgram(
                identifiedBy: identifier
            ) != nil else {
                throw ApplicationLaunchResolutionError
                    .programNotInstalled(
                        identifier
                    )
            }
        }
    }

    return entries
}
