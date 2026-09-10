import Agentic
import AgenticPrograms
import Foundation

public struct AgentProgramRunner: Sendable {
    public var services: AgentRuntimeServices

    public init(
        services: AgentRuntimeServices = .init()
    ) {
        self.services = services
    }

    public func execute<Program: AgentProgram>(
        _ program: Program,
        input: Program.Input,
        realization: AgentProgramRealization<Program>? = nil,
        metadata: [String: String] = [:]
    ) async throws -> AgentProgramExecution<Program> {
        let inputValue = try JSONToolBridge.encode(
            input
        )
        let trace = AgentProgramExecutionTrace()
        let startedAt = Date()
        let executionMetadata = services.metadata.merging(
            metadata
        ) { _, new in
            new
        }

        let inferenceInvoker: (any AgentInferenceInvoking)?
        if let inferenceExecutor = services.program.inference {
            inferenceInvoker = AgentProgramRecordingInferenceInvoker<Program>(
                executor: inferenceExecutor,
                realization: realization,
                trace: trace
            )
        } else {
            inferenceInvoker = nil
        }

        let toolInvoker: (any AgentProgramToolInvoking)?
        if let toolExecutor = services.program.tools {
            toolInvoker = AgentProgramRecordingToolInvoker(
                executor: toolExecutor,
                trace: trace
            )
        } else {
            toolInvoker = nil
        }

        let programInvoker: (any AgentProgramInvoking)?
        if let nestedProgramInvoker = services.program.invoker {
            programInvoker = AgentProgramRecordingProgramInvoker(
                invoker: nestedProgramInvoker,
                trace: trace
            )
        } else {
            programInvoker = nil
        }

        let context = AgentProgramContext(
            inference: inferenceInvoker,
            tools: toolInvoker,
            programs: programInvoker,
            artifacts: services.artifacts,
            metadata: executionMetadata
        )

        do {
            let output = try await program.run(
                input,
                in: context
            )
            let outputValue = try JSONToolBridge.encode(
                output
            )
            let completedAt = Date()
            let steps = await trace.snapshot()
            let record = AgentProgramExecutionRecord(
                programIdentifier: Program.descriptor.identifier,
                programVersion: Program.descriptor.version,
                realizationIdentifier: realization?.id,
                input: inputValue,
                output: outputValue,
                steps: steps,
                outcome: .succeeded,
                startedAt: startedAt,
                completedAt: completedAt,
                durationMilliseconds: agentProgramElapsedMilliseconds(
                    from: startedAt,
                    to: completedAt
                ),
                metadata: executionMetadata
            )

            return .init(
                output: output,
                record: record
            )
        } catch {
            let completedAt = Date()
            let steps = await trace.snapshot()
            let record = AgentProgramExecutionRecord(
                programIdentifier: Program.descriptor.identifier,
                programVersion: Program.descriptor.version,
                realizationIdentifier: realization?.id,
                input: inputValue,
                steps: steps,
                outcome: .failed,
                failure: .init(
                    error: error
                ),
                startedAt: startedAt,
                completedAt: completedAt,
                durationMilliseconds: agentProgramElapsedMilliseconds(
                    from: startedAt,
                    to: completedAt
                ),
                metadata: executionMetadata
            )

            return .init(
                output: nil,
                record: record
            )
        }
    }
}
