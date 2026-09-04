import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

struct AdapterFlowEchoTool: AgentTool {
    typealias Input = AdapterFlowEchoToolInput
    typealias Output = AdapterFlowEchoToolOutput

    static let identifier: AgentToolIdentifier = .init(
        "adapter_echo_tool"
    )
    static let description = "Echoes a value back to the model."
    static let risk: ActionRisk = .observe

    var identifier: AgentToolIdentifier {
        Self.identifier
    }

    var description: String {
        Self.description
    }

    var risk: ActionRisk {
        Self.risk
    }

    func call(
        _ input: Input,
        context _: AgentToolExecutionContext
    ) async throws -> Output {
        AdapterFlowEchoToolOutput(
            text: input.text
        )
    }
}

@JSONSchema
struct AdapterFlowEchoToolInput: Sendable, Codable, Hashable {
    var text: String
}

struct AdapterFlowEchoToolOutput: Sendable, Codable, Hashable {
    var text: String
}
