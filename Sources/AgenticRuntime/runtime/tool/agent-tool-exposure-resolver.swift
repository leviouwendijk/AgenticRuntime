import Agentic
import AgenticExecution
import AgenticTools

public enum AgentToolExposureBase:
    Sendable,
    Hashable
{
    case catalogDefaults
    case none
    case selected([AgentToolIdentifier])
    case all
}

public enum AgentToolExposureResolver {
    public static func resolve(
        base: AgentToolExposureBase,
        skills: [AgentSkill] = [],
        dynamicDiscovery: Bool,
        catalog: AgentToolCatalog
    ) -> AgentToolExposurePolicy {
        switch base {
        case .all:
            return .all

        case .catalogDefaults:
            return resolve(
                selectedIdentifiers:
                    catalog.defaultExposedIdentifiers,
                skills: skills,
                dynamicDiscovery: dynamicDiscovery,
                eligibleIdentifiers: Set(
                    catalog.modelFacingEntries.map(
                        \.identifier
                    )
                )
            )

        case .none:
            return resolve(
                selectedIdentifiers: [],
                skills: skills,
                dynamicDiscovery: dynamicDiscovery,
                eligibleIdentifiers: Set(
                    catalog.modelFacingEntries.map(
                        \.identifier
                    )
                )
            )

        case .selected(let identifiers):
            return resolve(
                selectedIdentifiers: identifiers,
                skills: skills,
                dynamicDiscovery: dynamicDiscovery,
                eligibleIdentifiers: Set(
                    catalog.modelFacingEntries.map(
                        \.identifier
                    )
                )
            )
        }
    }

    public static func resolve(
        selectedIdentifiers: [AgentToolIdentifier],
        skills: [AgentSkill] = [],
        dynamicDiscovery: Bool
    ) -> AgentToolExposurePolicy {
        resolve(
            selectedIdentifiers: selectedIdentifiers,
            skills: skills,
            dynamicDiscovery: dynamicDiscovery,
            eligibleIdentifiers: nil
        )
    }
}

private extension AgentToolExposureResolver {
    static func resolve(
        selectedIdentifiers: [AgentToolIdentifier],
        skills: [AgentSkill],
        dynamicDiscovery: Bool,
        eligibleIdentifiers: Set<AgentToolIdentifier>?
    ) -> AgentToolExposurePolicy {
        let requiredSkillIdentifiers = skills.flatMap { skill in
            skill.metadata.tools.required.map(
                \.identifier
            )
        }
        var identifiers = normalized(
            selectedIdentifiers
                + requiredSkillIdentifiers,
            eligibleIdentifiers: eligibleIdentifiers
        )
        let discoveryIsEligible =
            eligibleIdentifiers?.contains(
                FindToolsTool.identifier
            ) ?? true

        if dynamicDiscovery,
           discoveryIsEligible {
            identifiers.append(
                FindToolsTool.identifier
            )

            return .discoverable(
                identifiers
            )
        }

        return .explicit(
            identifiers
        )
    }

    static func normalized(
        _ identifiers: [AgentToolIdentifier],
        eligibleIdentifiers: Set<AgentToolIdentifier>?
    ) -> [AgentToolIdentifier] {
        var seen: Set<AgentToolIdentifier> = []
        var normalized: [AgentToolIdentifier] = []

        for identifier in identifiers {
            guard identifier != FindToolsTool.identifier else {
                continue
            }

            if let eligibleIdentifiers,
               !eligibleIdentifiers.contains(identifier) {
                continue
            }

            guard seen.insert(identifier).inserted else {
                continue
            }

            normalized.append(
                identifier
            )
        }

        return normalized
    }
}
