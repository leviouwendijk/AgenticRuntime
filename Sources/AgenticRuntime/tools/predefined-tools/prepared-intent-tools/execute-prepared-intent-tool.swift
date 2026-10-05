import Agentic
import Workspace
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

@JSONSchema
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

public struct ExecutePreparedIntentTool: Tool {
    public typealias Input = ExecutePreparedIntentToolInput
    public typealias Output = ExecutePreparedIntentToolOutput

    public static let identifier: ToolIdentifier = .execute_prepared_intent
    public static let description = "Execute an approved prepared intent through its stored versioned prepared operation."
    public static let risk: ActionRisk = .boundedmutate

    public static let definition: ToolDefinition = .init(
        identifier: Self.identifier,
        purpose: Self.description,
        risk: Self.risk
    )

    public let executor: PreparedIntentExecutor

    public init(
        executor: PreparedIntentExecutor
    ) {
        self.executor = executor
    }

    public func preflight(
        _ input: Input,
        in context: ToolContext
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

        let approved = intent.preflight
        let targets = approved.access.targets.isEmpty
            ? "none"
            : approved.access.targets.joined(
                separator: ", "
            )

        return .init(
            tool: Self.definition.identifier,
            risk: approved.risk,
            summary: """
            Execute approved prepared intent \(intent.id.rawValue).

            Status: \(intent.status.rawValue)
            Operation: \(intent.operation.schema.identifier.rawValue)
            Target: \(targets)
            """,
            access: approved.access,
            estimates: approved.estimates,
            preview: approved.preview,
            sideEffects: approved.sideEffects,
            policyChecks: approved.policyChecks + [
                "prepared_intent_approved",
            ],
            warnings: approved.warnings
        )
    }

    public func call(
        _ input: Input,
        in context: ToolContext
    ) async throws -> Output {
        let execution = try await executor.execute(
            id: input.id,
            context: .init(
                workspace: context.workspace,
                preparedIntentID: input.id
            )
        )

        return .init(
            intent: execution.intent,
            result: execution.result
        )
    }
}
