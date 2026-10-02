import Agentic
import Workspace
import Primitives
import Schema
import Macros

@JSONSchema
public struct ReviewPreparedIntentToolInput: Sendable, Codable, Hashable {
    public let id: PreparedIntentIdentifier
    public let decision: PreparedIntentReviewDecision
    public let reviewer: String?
    public let note: String?

    public init(
        id: PreparedIntentIdentifier,
        decision: PreparedIntentReviewDecision,
        reviewer: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.decision = decision
        self.reviewer = reviewer
        self.note = note
    }
}

@JSONSchema
public struct ReviewPreparedIntentToolOutput: Sendable, Codable, Hashable {
    public let intent: PreparedIntent

    public init(
        intent: PreparedIntent
    ) {
        self.intent = intent
    }
}

public struct ReviewPreparedIntentTool: Tool {
    public typealias Input = ReviewPreparedIntentToolInput
    public typealias Output = ReviewPreparedIntentToolOutput

    public static let identifier: ToolIdentifier = "review_prepared_intent"
    public static let description = "Approve, deny, cancel, or expire a prepared intent. This does not execute it."
    public static let risk: ActionRisk = .boundedmutate

    public static let definition: ToolDefinition = .init(
        identifier: Self.identifier,
        purpose: Self.description,
        risk: Self.risk
    )

    public var identifier: ToolIdentifier { Self.identifier }
    public var description: String { Self.description }
    public var risk: ActionRisk { Self.risk }

    public let manager: PreparedIntentManager

    public init(
        manager: PreparedIntentManager
    ) {
        self.manager = manager
    }

    public func preflight(
        _ input: Input,
        workspace: WorkspaceContext?
    ) async throws -> ToolPreflight {

        return .init(
            tool: Self.definition.identifier,
            risk: Self.definition.risk,
            summary: "Mark prepared intent \(input.id.rawValue) as \(input.decision.resolvedStatus.rawValue).",
            estimates: .init(
                write: .init(
                    count: 1
                )
            ),
            sideEffects: [
                "updates prepared intent review status"
            ]
        )
    }

    public func call(
        _ input: Input,
        workspace: WorkspaceContext?
    ) async throws -> Output {

        let intent = try await manager.review(
            id: input.id,
            decision: input.decision,
            reviewer: input.reviewer,
            note: input.note
        )

        return ReviewPreparedIntentToolOutput(
                intent: intent
            )
    }
}
