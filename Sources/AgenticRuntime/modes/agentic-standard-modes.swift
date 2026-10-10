import Agentic
import AgenticIO

public extension Mode {
    static let planning = Self(
        id: .planning,
        title: "Planning",
        routeDefaults: .init(
            primaryPurpose: .planner,
            selections: [
                .planner: .planner
            ]
        ),
        autonomyMode: .suggest_only,
        exposedToolIdentifiers: [],
        budgetPosture: .generous,
        approvalStrictness: .strict,
        metadata: [
            "intent": "strategy_without_mutation"
        ]
    )

    static let research = Self(
        id: .research,
        title: "Research",
        routeDefaults: .init(
            primaryPurpose: .researcher,
            selections: [
                .researcher: .researcher,
                .summarizer: .summarizer
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            SystemIO.Tools.ReadFile.identifier,
            SystemIO.Tools.ScanFilepaths.identifier
        ],
        budgetPosture: .balanced,
        approvalStrictness: .strict,
        metadata: [
            "intent": "observe_and_compress_context"
        ]
    )

    static let coder = Self(
        id: .coder,
        title: "Coder",
        routeDefaults: .init(
            primaryPurpose: .coder,
            selections: [
                .coder: .coder,
                .reviewer: .reviewer,
                .summarizer: .summarizer
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            SystemIO.Tools.ReadFile.identifier,
            SystemIO.Tools.ScanFilepaths.identifier,
            SystemIO.Tools.MutateFiles.identifier
        ],
        budgetPosture: .balanced,
        approvalStrictness: .review_bounded_mutation,
        metadata: [
            "intent": "bounded_code_implementation"
        ]
    )

    static let review = Self(
        id: .review,
        title: "Review",
        routeDefaults: .init(
            primaryPurpose: .reviewer,
            selections: [
                .reviewer: .reviewer,
                .summarizer: .summarizer
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            SystemIO.Tools.ReadFile.identifier,
            SystemIO.Tools.ScanFilepaths.identifier
        ],
        budgetPosture: .balanced,
        approvalStrictness: .strict,
        metadata: [
            "intent": "review_without_mutation"
        ]
    )

    static let debugging = Self(
        id: .debugging,
        title: "Debugging",
        routeDefaults: .init(
            primaryPurpose: .coder,
            selections: [
                .coder: .coder,
                .reviewer: .reviewer,
                .planner: .planner
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            SystemIO.Tools.ReadFile.identifier,
            SystemIO.Tools.ScanFilepaths.identifier,
            SystemIO.Tools.MutateFiles.identifier
        ],
        budgetPosture: .balanced,
        approvalStrictness: .review_bounded_mutation,
        metadata: [
            "intent": "diagnose_then_patch_with_review"
        ]
    )

    static let cheap_utility = Self(
        id: .cheap_utility,
        title: "Cheap utility",
        routeDefaults: .init(
            primaryPurpose: .classifier,
            selections: [
                .classifier: .classifier,
                .summarizer: .summarizer,
                .extractor: .extractor
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [],
        budgetPosture: .minimal,
        approvalStrictness: .relaxed_observe,
        metadata: [
            "intent": "cheap_classification_summary_extraction"
        ]
    )

    static let `private` = Self(
        id: .private,
        title: "Private",
        routeDefaults: .init(
            primaryPurpose: .local_private,
            selections: [
                .local_private: .local_private
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            SystemIO.Tools.ReadFile.identifier,
            SystemIO.Tools.ScanFilepaths.identifier
        ],
        budgetPosture: .local_only,
        approvalStrictness: .locked_down,
        metadata: [
            "intent": "local_private_only"
        ]
    )
}
