import Agentic
import AgenticExecution
import AgenticRuntime
import Foundation
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runPreparedIntentRuntimeExecution()
        async throws
        -> [TestFlowDiagnostic]
    {
        let preparedIntentsdir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "agentic-runtime-prepared-intent-\(UUID().uuidString)",
                    isDirectory: true
                )

        defer {
            try? FileManager.default.removeItem(
                at: preparedIntentsdir
            )
        }

        let manager = PreparedIntentManager(
            store: FilePreparedIntentStore(
                preparedIntentsdir: preparedIntentsdir
            )
        )
        var registry = PreparedOperationRegistry()

        try registry.register(
            RuntimePreparedOperationFixture()
        )

        let created = try await manager.create(
            PreparedIntentDraft(
                sessionID: "fixture-session",
                operation: try RuntimePreparedOperationFixture.envelope(
                    .init(
                        value: "payload"
                    )
                ),
                reviewPayload: .init(
                    title: "Execute Runtime prepared operation",
                    summary: "Exercise canonical Runtime prepared-operation execution.",
                    risk: .observe
                ),
                metadata: [
                    "fixture": "prepared-intent-runtime-execution",
                ]
            )
        )

        _ = try await manager.review(
            id: created.id,
            decision: .approve,
            reviewer: "fixture"
        )

        let executor = PreparedIntentExecutor(
            manager: manager,
            registry: registry,
            sessionID: "runtime-fallback-session"
        )
        let execution = try await executor.execute(
            id: created.id,
            context: .init(
                metadata: [
                    "flow": "prepared-intent-runtime-execution",
                ]
            )
        )
        let result = try RuntimePreparedOperationFixture.result(
            from: execution.result
        )

        try Expect.equal(
            result.value,
            "payload:fixture-session:\(created.id.rawValue)",
            "Runtime executes the exact prepared operation through PreparedOperationRegistry with intent identity and session context"
        )
        try Expect.equal(
            execution.intent.status,
            .executed,
            "Runtime records successful prepared-operation execution as the terminal intent state"
        )
        try Expect.equal(
            execution.intent.executionRecord?.operation,
            RuntimePreparedOperationFixture.schema,
            "Runtime execution evidence preserves the approved prepared-operation schema"
        )
        try Expect.equal(
            execution.intent.executionRecord?.result,
            execution.result,
            "Runtime persists the prepared-operation result envelope as execution evidence"
        )

        let runtimeRegistry =
            try AgenticRuntimePreparedOperations.registry()

        try Expect.equal(
            runtimeRegistry.schemas.map {
                $0.identifier.rawValue
            },
            [
                "file_mutation",
            ],
            "Runtime composition installs AgenticIO's executable prepared file mutation operation"
        )

        return [
            .field(
                "operation",
                execution.result.schema.identifier.rawValue
            ),
            .field(
                "status",
                execution.intent.status.rawValue
            ),
            .field(
                "runtime_registry",
                runtimeRegistry.schemas
                    .map { $0.identifier.rawValue }
                    .joined(separator: ",")
            ),
        ]
    }
}

private struct RuntimePreparedOperationFixture:
    AgentPreparedOperation,
    Sendable
{
    struct Plan: Sendable, Codable, Hashable {
        let value: String
    }

    struct Result: Sendable, Codable, Hashable {
        let value: String
    }

    static let schema = PreparedOperation.Schema(
        identifier: "runtime_fixture",
        version: .init(
            major: 0,
            minor: 1,
            patch: 0
        )
    )

    func execute(
        _ plan: Plan,
        context: PreparedOperation.Context
    ) async throws -> Result {
        .init(
            value: [
                plan.value,
                context.sessionID ?? "none",
                context.preparedIntentID?.rawValue ?? "none",
            ].joined(
                separator: ":"
            )
        )
    }
}
