import Agentic
import AgenticExecution
import AgenticStandard

public enum AgentToolExposureBase:
    Sendable,
    Hashable
{
    case catalogDefaults
    case none
    case selected([ToolIdentifier])
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
        selectedIdentifiers: [ToolIdentifier],
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
        selectedIdentifiers: [ToolIdentifier],
        skills: [AgentSkill],
        dynamicDiscovery: Bool,
        eligibleIdentifiers: Set<ToolIdentifier>?
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
                Standard.Tools.FindTools.identifier
            ) ?? true

        if dynamicDiscovery,
           discoveryIsEligible {
            identifiers.append(
                Standard.Tools.FindTools.identifier
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
        _ identifiers: [ToolIdentifier],
        eligibleIdentifiers: Set<ToolIdentifier>?
    ) -> [ToolIdentifier] {
        var seen: Set<ToolIdentifier> = []
        var normalized: [ToolIdentifier] = []

        for identifier in identifiers {
            guard identifier != Standard.Tools.FindTools.identifier else {
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
