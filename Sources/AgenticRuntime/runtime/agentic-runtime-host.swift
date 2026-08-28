import Agentic
import AgenticExecution
import AgenticInterfaces
import AgenticWorkspace

public extension AgenticRuntime {
    func host(
        workspacePath: String? = nil,
        sessionID: String? = nil,
        metadata: [String: String] = [:],
        approvalHandler: (any ToolApprovalHandler)? = nil
    ) throws -> AgenticToolHost {
        let workspace: AgentWorkspace?

        if let workspacePath {
            workspace = try AgenticRuntimeWorkspace.resolve(
                workspacePath
            )
        } else {
            workspace = nil
        }

        var hostMetadata = application.metadata
        hostMetadata["source"] =
            hostMetadata["source"]
            ?? application.identifier.rawValue

        for (key, value) in metadata {
            hostMetadata[key] = value
        }

        return AgenticToolHost(
            registry: tools,
            policy: ToolExecutionPolicy(
                autonomyMode: .auto_observe
            ),
            context: .init(
                workspace: workspace,
                sessionID: sessionID,
                executionMode: .host_call,
                metadata: hostMetadata
            ),
            approvalHandler: approvalHandler
        )
    }
}
