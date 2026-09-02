import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

struct AdapterFlowEchoTool: StaticAgentTool {
    static let identifier: AgentToolIdentifier = .init(
        "adapter_echo_tool"
    )
    static let description = "Echoes a value back to the model."
    static let risk: ActionRisk = .observe

    func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            AdapterFlowEchoToolInput.self,
            from: input
        )

        return try JSONToolBridge.encode(
            AdapterFlowEchoToolOutput(
                text: decoded.text
            )
        )
    }
}

struct AdapterFlowEchoToolInput: Sendable, Codable, Hashable {
    var text: String
}

struct AdapterFlowEchoToolOutput: Sendable, Codable, Hashable {
    var text: String
}
