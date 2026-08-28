import Agentic
import Foundation

public struct ModeContextDefaults: Sendable, Codable, Hashable {
    public var title: String
    public var details: String

    public init(
        title: String = "Agentic mode context",
        details: String = "Runtime mode metadata and loaded skill context."
    ) {
        self.title = title
        self.details = details
    }

    public static let `default` = Self()
}

public struct ModeContextApplication: Sendable, Codable, Hashable {
    public var plan: ContextCompositionPlan
    public var composed: ComposedContext
    public var message: AgentMessage?
    public var metadata: [String: String]

    public init(
        plan: ContextCompositionPlan,
        composed: ComposedContext,
        message: AgentMessage?,
        metadata: [String: String]
    ) {
        self.plan = plan
        self.composed = composed
        self.message = message
        self.metadata = metadata
    }
}

public extension ModeRuntimeApplication {
    func contextMetadata(
        defaults: ModeContextDefaults = .default,
        additionalMetadata: [String: String] = [:]
    ) -> ContextMetadata {
        ContextMetadata(
            title: defaults.title,
            details: defaults.details,
            attributes: requestMetadata(
                additionalMetadata: additionalMetadata
            )
        )
    }

    func contextPlan(
        defaults: ModeContextDefaults = .default,
        additionalSources: [ContextSource] = [],
        additionalMetadata: [String: String] = [:]
    ) -> ContextCompositionPlan {
        ContextCompositionPlan(
            metadata: contextMetadata(
                defaults: defaults,
                additionalMetadata: additionalMetadata
            ),
            sources: loadedSkills.map {
                .skill($0)
            } + additionalSources
        )
    }

    func composedContext(
        composer: ContextComposer = .init(),
        defaults: ModeContextDefaults = .default,
        additionalSources: [ContextSource] = [],
        additionalMetadata: [String: String] = [:]
    ) throws -> ComposedContext {
        try composer.compose(
            contextPlan(
                defaults: defaults,
                additionalSources: additionalSources,
                additionalMetadata: additionalMetadata
            )
        )
    }

    func contextMessage(
        role: AgentRole = .system,
        composer: ContextComposer = .init(),
        defaults: ModeContextDefaults = .default,
        additionalSources: [ContextSource] = [],
        additionalMetadata: [String: String] = [:]
    ) throws -> AgentMessage? {
        let composed = try composedContext(
            composer: composer,
            defaults: defaults,
            additionalSources: additionalSources,
            additionalMetadata: additionalMetadata
        )
        let text = composed.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            return nil
        }

        return AgentMessage(
            role: role,
            text: text
        )
    }

    func contextApplication(
        role: AgentRole = .system,
        composer: ContextComposer = .init(),
        defaults: ModeContextDefaults = .default,
        additionalSources: [ContextSource] = [],
        additionalMetadata: [String: String] = [:]
    ) throws -> ModeContextApplication {
        let plan = contextPlan(
            defaults: defaults,
            additionalSources: additionalSources,
            additionalMetadata: additionalMetadata
        )
        let composed = try composer.compose(
            plan
        )
        let text = composed.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let message = text.isEmpty
            ? nil
            : AgentMessage(
                role: role,
                text: text
            )

        return .init(
            plan: plan,
            composed: composed,
            message: message,
            metadata: requestMetadata(
                additionalMetadata: additionalMetadata
            )
        )
    }

    func request(
        user: String,
        system: String? = nil,
        composer: ContextComposer = .init(),
        generationConfiguration: AgentGenerationConfiguration = .default,
        additionalMetadata: [String: String] = [:]
    ) throws -> AgentRequest {
        var messages: [AgentMessage] = []

        if let system,
           !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(
                AgentMessage(
                    role: .system,
                    text: system
                )
            )
        }

        if let context = try contextMessage(
            composer: composer,
            additionalMetadata: additionalMetadata
        ) {
            messages.append(
                context
            )
        }

        messages.append(
            AgentMessage(
                role: .user,
                text: user
            )
        )

        return AgentRequest(
            messages: messages,
            tools: toolDefinitions,
            generationConfiguration: generationConfiguration,
            metadata: requestMetadata(
                additionalMetadata: additionalMetadata
            )
        )
    }

    func request(
        messages baseMessages: [AgentMessage],
        injectContextAtStart: Bool = true,
        composer: ContextComposer = .init(),
        generationConfiguration: AgentGenerationConfiguration = .default,
        additionalMetadata: [String: String] = [:]
    ) throws -> AgentRequest {
        var messages = baseMessages

        if let context = try contextMessage(
            composer: composer,
            additionalMetadata: additionalMetadata
        ) {
            if injectContextAtStart {
                messages.insert(
                    context,
                    at: 0
                )
            } else {
                messages.append(
                    context
                )
            }
        }

        return AgentRequest(
            messages: messages,
            tools: toolDefinitions,
            generationConfiguration: generationConfiguration,
            metadata: requestMetadata(
                additionalMetadata: additionalMetadata
            )
        )
    }

    private func requestMetadata(
        additionalMetadata: [String: String] = [:]
    ) -> [String: String] {
        var values = metadata

        values["mode_id"] = modeID.rawValue
        values["mode_title"] = selection.mode.title
        values["mode_route_purpose"] = routePolicy.purpose.rawValue
        values["mode_budget_posture"] = selection.budgetPosture.rawValue
        values["mode_approval_strictness"] = selection.approvalStrictness.rawValue
        values["mode_autonomy"] = configuration.autonomyMode.rawValue
        values["mode_loaded_skill_ids"] = loadedSkills
            .map(\.identifier.rawValue)
            .joined(separator: ",")
        values["mode_missing_skill_ids"] = missingSkillIdentifiers
            .map(\.rawValue)
            .joined(separator: ",")

        values.merge(
            additionalMetadata
        ) { _, new in
            new
        }

        return values
    }
}
