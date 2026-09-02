import Agentic
import AgenticExecution
import AgenticTools

public extension AgentToolExposurePolicy {
    static var discoveryOnly: Self {
        .discoverable(
            []
        )
    }

    static func skillSeeded(
        _ skills: [AgentSkill]
    ) -> Self {
        .discoverable(
            skills.flatMap { skill in
                (
                    skill.metadata.tools.required
                    + skill.metadata.tools.optional
                ).map(
                    \.identifier
                )
            }
        )
    }
}

extension AgentToolExposurePolicy {
    var resolvedForRuntime: Self {
        switch self {
        case .all,
             .explicit:
            return self

        case .discoverable(let identifiers):
            return .discoverable(
                [
                    FindToolsTool.identifier,
                ] + identifiers
            )
        }
    }

    var usesDiscovery: Bool {
        if case .discoverable = self {
            return true
        }

        return false
    }
}
