import Agentic
import AgenticExecution
import AgenticIO
import AgenticWorkspace
import Foundation
import Primitives

public enum ExecutePreparedIntentToolError: Error, Sendable, LocalizedError {
    case missingExecutionToolName(PreparedIntentIdentifier)
    case missingExactInputs(PreparedIntentIdentifier)
    case recursiveReplay(PreparedIntentIdentifier)
    case workspaceRequiredForFileMutation(PreparedIntentIdentifier)

    public var errorDescription: String? {
        switch self {
        case .missingExecutionToolName(let id):
            return "Prepared intent '\(id.rawValue)' is missing an execution tool name."

        case .missingExactInputs(let id):
            return "Prepared intent '\(id.rawValue)' is missing exact replay inputs."

        case .recursiveReplay(let id):
            return "Prepared intent '\(id.rawValue)' cannot replay through execute_prepared_intent."

        case .workspaceRequiredForFileMutation(let id):
            return "Prepared file mutation intent '\(id.rawValue)' requires a workspace for approval-time drift checks."
        }
    }
}

public struct ExecutePreparedIntentToolInput: Sendable, Codable, Hashable {
    public let id: PreparedIntentIdentifier

    public init(
        id: PreparedIntentIdentifier
    ) {
        self.id = id
    }
}

public struct ExecutePreparedIntentToolOutput: Sendable, Codable, Hashable {
    public let intent: PreparedIntent
    public let toolCall: AgentToolCall
    public let toolResult: AgentToolResult

    public init(
        intent: PreparedIntent,
        toolCall: AgentToolCall,
        toolResult: AgentToolResult
    ) {
        self.intent = intent
        self.toolCall = toolCall
        self.toolResult = toolResult
    }
}

public struct ExecutePreparedIntentTool: AgentTool {
    public let identifier: AgentToolIdentifier = .execute_prepared_intent
    public let description = "Execute an approved prepared intent by replaying its exact tool call."
    public let risk: ActionRisk = .boundedmutate

    public let manager: PreparedIntentManager
    public let registry: ToolRegistry
    public let sessionID: String?

    public init(
        manager: PreparedIntentManager,
        registry: ToolRegistry,
        sessionID: String? = nil
    ) {
        self.manager = manager
        self.registry = registry
        self.sessionID = sessionID
    }

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            ExecutePreparedIntentToolInput.self,
            from: input
        )
        let intent = try await manager.get(
            decoded.id
        )
        let toolName = try executionToolName(
            for: intent
        )

        _ = try registeredTool(
            named: toolName
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            targetPaths: intent.reviewPayload.target.map { [$0] } ?? [],
            summary: """
            Execute prepared intent \(intent.id.rawValue).

            Status: \(intent.status.rawValue)
            Action type: \(intent.actionType)
            Execution tool: \(toolName)
            Target: \(intent.reviewPayload.target ?? "none")
            """,
            estimatedRuntimeSeconds: 1,
            sideEffects: intent.reviewPayload.expectedSideEffects,
            capabilitiesRequired: [
                .write
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            ExecutePreparedIntentToolInput.self,
            from: input
        )
        let startedAt = Date()
        let executableIntent = try await manager.executableIntent(
            id: decoded.id
        )

        do {
            let toolName = try executionToolName(
                for: executableIntent
            )
            let exactInputs = try exactInputs(
                for: executableIntent
            )

            try requirePreparedFileMutationApproval(
                executableIntent,
                toolName: toolName,
                workspace: workspace
            )

            let metadata = executionMetadata(
                for: executableIntent,
                toolName: toolName
            )
            let toolCall = AgentToolCall(
                id: "prepared-\(executableIntent.id.rawValue)",
                name: toolName,
                input: exactInputs
            )
            let toolResult = try await registry.execute(
                toolCall,
                context: .init(
                    workspace: workspace,
                    sessionID: executableIntent.sessionID ?? sessionID,
                    toolCallID: toolCall.id,
                    preparedIntentID: executableIntent.id,
                    executionMode: .prepared_intent_replay,
                    metadata: metadata
                )
            )
            let executed = try await manager.recordExecution(
                id: executableIntent.id,
                record: .init(
                    intentID: executableIntent.id,
                    executionToolName: toolName,
                    status: .succeeded,
                    summary: "Executed prepared intent by replaying \(toolName).",
                    startedAt: startedAt,
                    completedAt: Date(),
                    result: toolResult.output,
                    metadata: metadata
                )
            )

            return try JSONToolBridge.encode(
                ExecutePreparedIntentToolOutput(
                    intent: executed,
                    toolCall: toolCall,
                    toolResult: toolResult
                )
            )
        } catch {
            _ = try? await manager.recordExecution(
                id: executableIntent.id,
                record: .init(
                    intentID: executableIntent.id,
                    executionToolName: executableIntent.executionToolName,
                    status: .failed,
                    summary: "Prepared intent tool-call replay failed.",
                    startedAt: startedAt,
                    completedAt: Date(),
                    result: nil,
                    errorMessage: String(
                        describing: error
                    ),
                    metadata: [
                        "execution_mode": AgentToolExecutionMode.prepared_intent_replay.rawValue,
                        "prepared_intent_id": executableIntent.id.rawValue,
                        "actionType": executableIntent.actionType
                    ]
                )
            )

            throw error
        }
    }
}

private extension ExecutePreparedIntentTool {
    func requirePreparedFileMutationApproval(
        _ intent: PreparedIntent,
        toolName: String,
        workspace: AgentWorkspace?
    ) throws {
        guard let action = FileMutationIntentAction(
            actionType: intent.actionType
        ) else {
            return
        }

        guard action != .rollback else {
            return
        }

        guard let workspace else {
            throw ExecutePreparedIntentToolError.workspaceRequiredForFileMutation(
                intent.id
            )
        }

        let approval = try AgentFileMutationApproval.approval(
            for: intent,
            action: action
        )

        try approval?.requireCurrentFile(
            in: workspace,
            toolName: toolName
        )
    }

    func executionToolName(
        for intent: PreparedIntent
    ) throws -> String {
        guard let value = normalized(
            intent.executionToolName
        ) else {
            throw ExecutePreparedIntentToolError.missingExecutionToolName(
                intent.id
            )
        }

        guard value != AgentToolIdentifier.execute_prepared_intent.rawValue else {
            throw ExecutePreparedIntentToolError.recursiveReplay(
                intent.id
            )
        }

        return value
    }

    func exactInputs(
        for intent: PreparedIntent
    ) throws -> JSONValue {
        guard let exactInputs = intent.reviewPayload.exactInputs else {
            throw ExecutePreparedIntentToolError.missingExactInputs(
                intent.id
            )
        }

        return exactInputs
    }

    func registeredTool(
        named name: String
    ) throws -> any AgentTool {
        guard let tool = registry.tool(
            named: name
        ) else {
            throw ToolRegistryExecutionError.missingTool(
                name
            )
        }

        return tool
    }

    func executionMetadata(
        for intent: PreparedIntent,
        toolName: String
    ) -> [String: String] {
        var metadata = intent.metadata

        metadata.merge(
            intent.reviewPayload.metadata
        ) { old, _ in
            old
        }

        metadata["execution_mode"] = AgentToolExecutionMode.prepared_intent_replay.rawValue
        metadata["prepared_intent_id"] = intent.id.rawValue
        metadata["actionType"] = intent.actionType
        metadata["toolName"] = toolName

        return metadata
    }

    func normalized(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? nil : trimmed
    }
}
