import Agentic
import AgenticRuntime
import Foundation
import TestFlows

private enum RunLimitFixtureError:
    Error,
    Sendable
{
    case unexpected_model_invocation
}

private struct RunLimitNeverInvoker:
    AgentModelInvoking
{
    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocationResult {
        _ = invocation
        throw RunLimitFixtureError.unexpected_model_invocation
    }

    func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<AgentModelInvocationEvent, Error> {
        _ = invocation

        return AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: RunLimitFixtureError.unexpected_model_invocation
            )
        }
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runAgentRunLimitStop()
        async throws
        -> [TestDiagnostic]
    {
        let sessionsdir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-run-limit-stop-\(UUID().uuidString)",
                isDirectory: true
            )

        defer {
            try? FileManager.default.removeItem(
                at: sessionsdir
            )
        }

        let historyStore = FileHistoryStore(
            sessionsdir: sessionsdir
        )
        let sessionID = "fixture-run-limit-stop"
        let request = AgentRequest(
            messages: [
                Message(
                    role: .user,
                    text: "Exercise explicit run-limit stop."
                ),
            ]
        )
        let exhaustion = AgentRunLimitExhaustion.iterations(
            limit: 1,
            consumed: 1
        )
        let suspension = AgentSuspension.run_limit(
            exhaustion
        )
        let checkpoint = AgentHistoryCheckpoint(
            id: sessionID,
            originalRequest: request,
            state: .init(
                iteration: 1,
                messages: request.messages
            ),
            runLimits: .init(
                iterations: 1
            ),
            phase: .suspended,
            suspension: suspension
        )

        try await historyStore.saveCheckpoint(
            checkpoint
        )

        let runner = AgentRunner(
            model: .init(
                invoker: RunLimitNeverInvoker()
            ),
            configuration: .init(
                runLimits: .init(
                    iterations: 1
                ),
                historyPersistenceMode: .checkpointmutation
            ),
            recording: .init(
                historyStore: historyStore
            )
        )
        let interactionRequest = AgentInteraction.Request(
            sessionID: sessionID,
            suspension: suspension
        )
        let result = try await runner.resume(
            interaction: AgentInteraction.Response(
                request: interactionRequest,
                resolution: .run_limit(
                    .stop
                )
            )
        )

        try Expect.equal(
            result.phase,
            .interrupted,
            "explicit run-limit stop produces an interrupted result"
        )
        try Expect.equal(
            result.isInterrupted,
            true,
            "interrupted result exposes authoritative interrupted state"
        )
        try Expect.equal(
            result.isFailed,
            false,
            "run-limit stop is not failure"
        )
        try Expect.equal(
            result.isSuspended,
            false,
            "run-limit stop clears the suspension"
        )
        try Expect.equal(
            result.isCompleted,
            false,
            "run-limit stop is distinct from normal completion"
        )
        try Expect.equal(
            result.failure,
            nil,
            "run-limit stop carries no AgentRunFailure"
        )
        try Expect.equal(
            result.suspension,
            nil,
            "run-limit stop returns no unresolved suspension"
        )
        try Expect.equal(
            result.state.iteration,
            1,
            "run-limit stop preserves cumulative iteration consumption"
        )
        try Expect.equal(
            result.events.last?.kind,
            Optional(AgentRunEvent.Kind.run_limit_stopped),
            "run-limit stop records a distinct terminal interruption event"
        )

        let persisted = try Expect.notNil(
            try await historyStore.loadCheckpoint(
                sessionID: sessionID
            ),
            "run-limit stop remains durably inspectable"
        )

        try Expect.equal(
            persisted.phase,
            .interrupted,
            "durable checkpoint records interrupted phase"
        )
        try Expect.equal(
            persisted.suspension,
            nil,
            "durable interrupted checkpoint clears run-limit suspension"
        )
        try Expect.equal(
            persisted.failure,
            nil,
            "durable interrupted checkpoint remains nonfailure"
        )
        try Expect.equal(
            persisted.runLimits,
            AgentRunLimits(
                iterations: 1
            ),
            "stopping does not rewrite the limit that caused the boundary"
        )
        try Expect.equal(
            persisted.events.last?.kind,
            Optional(AgentRunEvent.Kind.run_limit_stopped),
            "durable checkpoint retains the explicit stop event"
        )

        let restored = try await runner.resume(
            sessionID: sessionID
        )

        try Expect.equal(
            restored.phase,
            .interrupted,
            "loading an interrupted run returns its state instead of throwing"
        )
        try Expect.equal(
            restored.isInterrupted,
            true,
            "restored interrupted state remains explicit"
        )
        try Expect.equal(
            restored.isFailed,
            false,
            "restored interrupted run remains nonfailure"
        )

        return [
            .field(
                "phase",
                result.phase.rawValue
            ),
            .field(
                "iteration",
                String(result.state.iteration)
            ),
            .field(
                "restored_phase",
                restored.phase.rawValue
            ),
        ]
    }
}
