import Agentic
import AgenticExecution
import Foundation
import Primitives
import Schema
import Macros

@JSONSchema
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
    public let result: PreparedOperation.ResultEnvelope

    public init(
        intent: PreparedIntent,
        result: PreparedOperation.ResultEnvelope
    ) {
        self.intent = intent
        self.result = result
    }
}

public struct ExecutePreparedIntentTool: AgentTool {
    public typealias Input = ExecutePreparedIntentToolInput
    public typealias Output = ExecutePreparedIntentToolOutput

    public let identifier: AgentToolIdentifier = .execute_prepared_intent
    public let description = "Execute an approved prepared intent through its stored versioned prepared operation."
    public let risk: ActionRisk = .boundedmutate

    public let executor: PreparedIntentExecutor

    public init(
        executor: PreparedIntentExecutor
    ) {
        self.executor = executor
    }

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        let intent = try await executor.manager.executableIntent(
            id: input.id
        )

        guard executor.contains(
            intent.operation.schema
        ) else {
            throw PreparedOperationRegistryError.unregisteredSchema(
                intent.operation.schema
            )
        }

        return .init(
            toolName: name,
            risk: intent.reviewPayload.risk,
            workspaceRoot: context.workspace?.rootURL.path,
            targetPaths: intent.reviewPayload.target.map { [$0] } ?? [],
            summary: """
            Execute approved prepared intent \(intent.id.rawValue).

            Status: \(intent.status.rawValue)
            Operation: \(intent.operation.schema.identifier.rawValue)
            Target: \(intent.reviewPayload.target ?? "none")
            """,
            estimatedRuntimeSeconds: 1,
            sideEffects: intent.reviewPayload.expectedSideEffects
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let execution = try await executor.execute(
            id: input.id,
            context: .init(
                workspace: context.workspace,
                workspaceLocation: context.workspaceLocation,
                sessionID: context.sessionID,
                preparedIntentID: input.id,
                metadata: context.metadata
            )
        )

        return .init(
            intent: execution.intent,
            result: execution.result
        )
    }
}
