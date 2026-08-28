import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

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

public struct ReviewPreparedIntentToolOutput: Sendable, Codable, Hashable {
    public let intent: PreparedIntent

    public init(
        intent: PreparedIntent
    ) {
        self.intent = intent
    }
}

public struct ReviewPreparedIntentTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "review_prepared_intent"
    public static let description = "Approve, deny, cancel, or expire a prepared intent. This does not execute it."
    public static let risk: ActionRisk = .boundedmutate

    public var identifier: AgentToolIdentifier { Self.identifier }
    public var description: String { Self.description }
    public var risk: ActionRisk { Self.risk }

    public let manager: PreparedIntentManager

    public init(
        manager: PreparedIntentManager
    ) {
        self.manager = manager
    }

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            ReviewPreparedIntentToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Mark prepared intent \(decoded.id.rawValue) as \(decoded.decision.resolvedStatus.rawValue).",
            estimatedWriteCount: 1,
            sideEffects: [
                "updates prepared intent review status"
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            ReviewPreparedIntentToolInput.self,
            from: input
        )

        let intent = try await manager.review(
            id: decoded.id,
            decision: decoded.decision,
            reviewer: decoded.reviewer,
            note: decoded.note
        )

        return try JSONToolBridge.encode(
            ReviewPreparedIntentToolOutput(
                intent: intent
            )
        )
    }
}
