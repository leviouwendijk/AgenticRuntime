import Agentic
import AgenticIO

public extension AgenticMode {
    static let planning = Self(
        id: .planning,
        title: "Planning",
        routeDefaults: .init(
            primaryPurpose: .planner,
            policies: [
                .planner: .planner
            ]
        ),
        autonomyMode: .suggest_only,
        exposedToolIdentifiers: [],
        loadedSkillIdentifiers: [
            "context-packing",
            "handoff-summary",
            "evidence-citation"
        ],
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
            policies: [
                .researcher: .researcher,
                .summarizer: .summarizer
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            ReadFileTool.identifier,
            ScanPathsTool.identifier
        ],
        loadedSkillIdentifiers: [
            "context-packing",
            "tool-first-retrieval",
            "evidence-citation"
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
            policies: [
                .coder: .coder,
                .reviewer: .reviewer,
                .summarizer: .summarizer
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            ReadFileTool.identifier,
            ScanPathsTool.identifier,
            MutateFilesTool.identifier
        ],
        loadedSkillIdentifiers: [
            "safe-file-editing",
            "context-packing",
            "refactoring-plan",
            "failure-triage"
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
            policies: [
                .reviewer: .reviewer,
                .summarizer: .summarizer
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            ReadFileTool.identifier,
            ScanPathsTool.identifier
        ],
        loadedSkillIdentifiers: [
            "evidence-citation",
            "failure-triage",
            "approval-sensitive-actions"
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
            policies: [
                .coder: .coder,
                .reviewer: .reviewer,
                .planner: .planner
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            ReadFileTool.identifier,
            ScanPathsTool.identifier,
            MutateFilesTool.identifier
        ],
        loadedSkillIdentifiers: [
            "debugging-loop",
            "failure-triage",
            "safe-file-editing",
            "evidence-citation"
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
            policies: [
                .classifier: .classifier,
                .summarizer: .summarizer,
                .extractor: .extractor
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [],
        loadedSkillIdentifiers: [
            "cost-aware-contexting",
            "transcript-summarization"
        ],
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
            policies: [
                .local_private: .local_private
            ]
        ),
        autonomyMode: .auto_observe,
        exposedToolIdentifiers: [
            ReadFileTool.identifier,
            ScanPathsTool.identifier
        ],
        loadedSkillIdentifiers: [
            "privacy-discipline",
            "cost-aware-contexting"
        ],
        budgetPosture: .local_only,
        approvalStrictness: .locked_down,
        metadata: [
            "intent": "local_private_only"
        ]
    )
}
