import Agentic
import AgenticIO
import AgenticStandard
import Workspace
import Foundation
import Primitives

extension AgentLoop {
    func saveCheckpoint(
        _ checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let root_id = AgentExecutionInvocation.root_id(session_id: checkpoint.id)
        if let index = checkpoint.invocations.firstIndex(where: { $0.id == root_id }) {
            let phase_state: AgentExecutionInvocation.State
            switch checkpoint.phase {
            case .completed: phase_state = .completed
            case .failed: phase_state = .failed
            case .interrupted: phase_state = .interrupted
            case .suspended, .awaiting_approval: phase_state = .suspended
            case .ready_for_model, .receiving_model_response, .processing_tool_calls:
                phase_state = .running
            }
            if checkpoint.invocations[index].state != phase_state {
                checkpoint.invocations[index].transition(to: phase_state)
            }
        }
        checkpoint.capabilities =
            await capabilityState.snapshot()
        if configuration.contextMode == .dynamic, let contextAllocator {
            checkpoint.contextWorkingSet = try await contextAllocator.snapshot(checkpoint.id)
            checkpoint.contextTransitions = await contextAllocator.recordedOperations(for: checkpoint.id)
        }
        checkpoint.touch()

        await publishRunState(
            checkpoint
        )

        guard configuration.persistsHistory else {
            return
        }

        guard let historyStore = recording.historyStore else {
            return
        }

        try await historyStore.saveCheckpoint(
            checkpoint
        )
    }

    func publishRunState(
        _ checkpoint: AgentExecutor.Checkpoint
    ) async {
        guard !recording.stateSinks.isEmpty else {
            return
        }

        let snapshot = AgentRunStateSnapshot(
            checkpoint: checkpoint
        )

        for sink in recording.stateSinks {
            await sink.publish(
                snapshot
            )
        }
    }

    func appendRunEvent(
        _ event: Run.Event.State,
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        try observe_invocation_event(event, in: &checkpoint)
        checkpoint.events.append(
            event
        )

        try await record(
            .state(event)
        )
    }

    func recordMessage(
        _ message: Message
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordMessage(
                message
            )
        }
    }

    func recordMessages(
        _ messages: [Message]
    ) async throws {
        for message in messages {
            try await recordMessage(
                message
            )
        }
    }

    func recordFunctionCall(
        _ functionCall: FunctionCall
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordFunctionCall(
                functionCall
            )
        }
    }

    func recordToolResult(
        _ result: FunctionCall.Response
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordToolResult(
                result
            )
        }
    }

    func record(
        _ event: Run.Event
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.record(
                event
            )
        }
    }
}
