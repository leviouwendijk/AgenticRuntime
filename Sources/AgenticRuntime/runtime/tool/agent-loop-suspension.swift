import Agentic
import AgenticIO
import AgenticStandard
import Workspace
import Foundation
import Primitives

extension AgentLoop {
    func suspendedResult(
        from checkpoint: AgentExecutor.Checkpoint
    ) throws -> AgentExecutor.Result {
        guard let suspension = checkpoint.resolvedSuspension else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without suspension payload"
            )
        }

        return .suspended(
            sessionID: checkpoint.id,
            phase: checkpoint.phase,
            response: checkpoint.lastResponse,
            suspension: suspension,
            state: checkpoint.state,
            events: checkpoint.events,
            toolUses: checkpoint.resolvedToolUses,
            costRecord: checkpoint.costRecord,
                invocations: checkpoint.invocations
        )
    }

    func suspendForUserInput(
        _ invocation: ToolInvocation,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> AgentExecutor.Result {
        let input = try JSONCoding.default.decode(
            Standard.Tools.ClarifyWithUser.Input.self,
            from: invocation.arguments
        )
        let request = try input.request()
        let suspension = Run.Suspension.user_input(
            request,
            metadata: [
                "callID": invocation.id,
                "toolName": invocation.tool.rawValue
            ]
        )

        checkpoint.suspend(
            suspension
        )

        try await appendRunEvent(
            .init(
                kind: .pending_user_input,
                iteration: checkpoint.state.iteration,
                callID: invocation.id,
                toolName: invocation.tool.rawValue,
                summary: request.prompt
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        return try suspendedResult(
            from: checkpoint
        )
    }

    func suspendForWorkspaceAccess(
        _ request: WorkspaceAccessRequest,
        functionCall: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> AgentExecutor.Result {
        let suspension = Run.Suspension.workspace_access(
            request,
            metadata: [
                "callID": functionCall.id,
                "toolName": functionCall.name
            ]
        )

        checkpoint.suspend(
            suspension
        )

        try await appendRunEvent(
            .init(
                kind: .pending_workspace_access,
                iteration: checkpoint.state.iteration,
                callID: functionCall.id,
                toolName: functionCall.name,
                summary: "workspace access resolution required"
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        return try suspendedResult(
            from: checkpoint
        )
    }
}
