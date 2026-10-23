import Agentic
import Foundation

public struct PreparedIntentExecution: Sendable, Codable, Hashable {
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

public struct PreparedIntentExecutor: Sendable {
    public let manager: PreparedIntentManager
    public let registry: PreparedOperationRegistry
    public let sessionID: String?

    public init(
        manager: PreparedIntentManager,
        registry: PreparedOperationRegistry,
        sessionID: String? = nil
    ) {
        self.manager = manager
        self.registry = registry
        self.sessionID = sessionID
    }

    public func contains(
        _ schema: PreparedOperation.Schema
    ) -> Bool {
        registry.contains(
            schema
        )
    }

    public func execute(
        id: PreparedIntentIdentifier,
        context: PreparedOperation.Context = .init()
    ) async throws -> PreparedIntentExecution {
        // One authoritative PreparedIntentManager execution path owns the
        // transition into .executing and its terminal execution record.
        let prepared_intent = try await manager.get(id)
        var metadata = prepared_intent.metadata
        metadata.merge(context.metadata) { _, new in new }
        metadata["execution_mode"] = "prepared_operation"
        metadata["prepared_intent_id"] = id.rawValue
        metadata["operation_identifier"] = prepared_intent.operation.schema.identifier.rawValue
        let merged = PreparedOperation.Context(
            workspace: context.workspace,
            sessionID: context.sessionID ?? sessionID,
            preparedIntentID: id,
            metadata: metadata
        )
        let intent = try await manager.execute(
            id: id,
            using: registry,
            context: merged
        )
        guard let result = intent.executionResult else {
            throw PreparedIntentExecutionError.missing_result(id)
        }
        return .init(intent: intent, result: result)
    }

}

public enum PreparedIntentExecutionError: Error, Sendable {
    case missing_result(PreparedIntentIdentifier)
}
