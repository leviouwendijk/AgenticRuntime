import Agentic
import AgenticExecution

public extension AgentToolExposurePolicy {
    static var discoveryOnly: Self {
        AgentToolExposureResolver.resolve(
            selectedIdentifiers: [],
            dynamicDiscovery: true
        )
    }

    static func skillSeeded(
        _ skills: [AgentSkill]
    ) -> Self {
        AgentToolExposureResolver.resolve(
            selectedIdentifiers: [],
            skills: skills,
            dynamicDiscovery: true
        )
    }
}

extension AgentToolExposurePolicy {
    var usesDiscovery: Bool {
        if case .discoverable = self {
            return true
        }

        return false
    }
}
