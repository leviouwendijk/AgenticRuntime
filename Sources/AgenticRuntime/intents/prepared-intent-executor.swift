import Agentic
import AgenticExecution
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
        let startedAt = Date()
        let intent = try await manager.executableIntent(
            id: id
        )
        var metadata = intent.metadata

        metadata.merge(
            context.metadata
        ) { _, new in
            new
        }

        metadata["execution_mode"] = "prepared_operation"
        metadata["prepared_intent_id"] = intent.id.rawValue
        metadata["operation_identifier"] =
            intent.operation.schema.identifier.rawValue

        let operationContext = PreparedOperation.Context(
            workspace: context.workspace,
            workspaceLocation: context.workspaceLocation,
            sessionID:
                intent.sessionID
                ?? context.sessionID
                ?? sessionID,
            preparedIntentID: intent.id,
            metadata: metadata
        )

        do {
            let result = try await registry.execute(
                intent.operation,
                context: operationContext
            )
            let executed = try await manager.recordExecution(
                id: intent.id,
                record: .init(
                    intentID: intent.id,
                    operation: intent.operation.schema,
                    status: .succeeded,
                    summary: "Executed prepared operation '\(intent.operation.schema.identifier.rawValue)'.",
                    startedAt: startedAt,
                    completedAt: Date(),
                    result: result,
                    metadata: metadata
                )
            )

            return .init(
                intent: executed,
                result: result
            )
        } catch {
            _ = try? await manager.recordExecution(
                id: intent.id,
                record: .init(
                    intentID: intent.id,
                    operation: intent.operation.schema,
                    status: .failed,
                    summary: "Prepared operation '\(intent.operation.schema.identifier.rawValue)' failed.",
                    startedAt: startedAt,
                    completedAt: Date(),
                    result: nil,
                    errorMessage: errorText(
                        error
                    ),
                    metadata: metadata
                )
            )

            throw error
        }
    }
}

private extension PreparedIntentExecutor {
    func errorText(
        _ error: any Error
    ) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription
        {
            return description
        }

        return String(
            describing: error
        )
    }
}
