import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

actor AdapterFlowScratchpadStore {
    private var values: [String] = []

    func append(
        _ value: String
    ) -> Int {
        values.append(
            value
        )

        return values.count
    }

    func all() -> [String] {
        values
    }
}

struct AdapterFlowScratchpadReadTool: TypedAgentTool {
    typealias Input = AdapterFlowScratchpadReadInput

    static let identifier: AgentToolIdentifier = .init(
        "adapter_scratchpad_read"
    )
    static let description = "Reads notes from an in-memory test scratchpad."
    static let risk: ActionRisk = .observe

    let store: AdapterFlowScratchpadStore

    func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = input
        _ = workspace

        let values = await store.all()

        return try JSONToolBridge.encode(
            AdapterFlowScratchpadReadOutput(
                values: values,
                count: values.count
            )
        )
    }
}

struct AdapterFlowScratchpadTool: TypedAgentTool {
    typealias Input = AdapterFlowScratchpadPutInput

    static let identifier: AgentToolIdentifier = .init(
        "adapter_scratchpad_put"
    )
    static let description = "Stores a note in an in-memory test scratchpad."
    static let risk: ActionRisk = .boundedmutate

    let store: AdapterFlowScratchpadStore

    func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            AdapterFlowScratchpadPutInput.self,
            from: input
        )
        let count = await store.append(
            decoded.text
        )

        return try JSONToolBridge.encode(
            AdapterFlowScratchpadPutOutput(
                text: decoded.text,
                count: count
            )
        )
    }
}

@JSONSchema
struct AdapterFlowScratchpadReadInput: Sendable, Codable, Hashable {
    init() {}
}

struct AdapterFlowScratchpadReadOutput: Sendable, Codable, Hashable {
    var values: [String]
    var count: Int
}

@JSONSchema
struct AdapterFlowScratchpadPutInput: Sendable, Codable, Hashable {
    var text: String
}

struct AdapterFlowScratchpadPutOutput: Sendable, Codable, Hashable {
    var text: String
    var count: Int
}
