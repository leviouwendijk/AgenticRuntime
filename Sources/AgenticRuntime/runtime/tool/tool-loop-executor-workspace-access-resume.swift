import Agentic
import AgenticIO

extension ToolLoopExecutor {
    func resumeWithWorkspaceAccess(
        _ checkpoint: AgentHistoryCheckpoint,
        resolution: WorkspaceAccessResolution,
        metadata: [String: String]
    ) async throws -> AgentRunResult {
        var checkpoint = checkpoint

        guard checkpoint.phase == .suspended
            || checkpoint.phase == .awaiting_approval
        else {
            throw AgentHistoryError.corruptedCheckpoint(
                "resume workspace access without suspended checkpoint"
            )
        }

        guard let suspension = checkpoint.resolvedSuspension,
              case .workspace_access = suspension.reason
        else {
            throw AgentHistoryError.corruptedCheckpoint(
                "resume workspace access without workspace-access suspension"
            )
        }

        guard let toolCallID = suspension.metadata["toolCallID"] else {
            throw AgentHistoryError.corruptedCheckpoint(
                "workspace-access suspension without tool call id"
            )
        }

        let toolName = suspension.metadata["toolName"]
            ?? RequestPathGrantTool.identifier.rawValue
        var payloadMetadata = suspension.metadata

        payloadMetadata.merge(
            metadata
        ) { _, new in
            new
        }

        let result = AgentToolResult(
            toolCallID: toolCallID,
            name: toolName,
            output: try JSONToolBridge.encode(
                WorkspaceAccessResumePayload(
                    kind: resolution == .deny
                        ? "workspace_access_denied"
                        : "workspace_access_granted",
                    resolution: resolution,
                    metadata: payloadMetadata
                )
            ),
            isError: false
        )
        let toolCall = AgentToolCall(
            id: toolCallID,
            name: toolName,
            input: .object([:])
        )

        try await appendToolResult(
            result,
            for: toolCall,
            disposition: .executed,
            to: &checkpoint,
            summary: resolution == .deny
                ? "workspace access denied"
                : "workspace access granted"
        )

        try await appendSkippedSiblings(
            after: toolCallID,
            to: &checkpoint,
            disposition: .skipped_after_workspace_access,
            reason: workspaceAccessSiblingReason
        )

        finishToolBatch(
            on: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        return try await runLoop(
            from: checkpoint
        )
    }
}
