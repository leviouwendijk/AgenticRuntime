import Agentic
import AgenticPrograms
import Foundation
import Primitives

actor AgentProgramExecutionTrace {
    private var nextIndex = 0
    private var records: [AgentProgramStepRecord] = []

    func reserveIndex() -> Int {
        let index = nextIndex
        nextIndex += 1
        return index
    }

    func append(
        _ record: AgentProgramStepRecord
    ) {
        records.append(
            record
        )
    }

    func snapshot() -> [AgentProgramStepRecord] {
        records.sorted {
            $0.index < $1.index
        }
    }
}

struct AgentProgramRecordingInferenceInvoker<Program: AgentProgram>:
    AgentInferenceInvoking
{
    let executor: any AgentProgramInferenceExecuting
    let realization: AgentProgramRealization<Program>?
    let trace: AgentProgramExecutionTrace

    func infer<Inference: AgentInference>(
        _ inference: Inference.Type,
        at site: AgentInferenceSiteIdentifier,
        input: Inference.Input
    ) async throws -> Inference.Output {
        let inputValue = try JSONToolBridge.encode(
            input
        )
        let index = await trace.reserveIndex()
        let startedAt = Date()
        var appliedRealization: AgentInferenceRealization?

        do {
            let inferenceIdentifier = Inference.definition.identifier

            guard let binding = realization?.inference(
                at: site
            ) else {
                throw AgentProgramRuntimeError
                    .missingInferenceRealization(
                        site: site,
                        inference: inferenceIdentifier
                    )
            }

            appliedRealization = binding.realization

            guard binding.inference == inferenceIdentifier else {
                throw AgentProgramRuntimeError
                    .inferenceRealizationMismatch(
                        site: site,
                        expected: inferenceIdentifier,
                        actual: binding.inference
                    )
            }

            let execution = try await executor.infer(
                inference,
                input: input,
                realization: binding.realization
            )
            let outputValue = try JSONToolBridge.encode(
                execution.output
            )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .inference(
                        site: site,
                        inference: inferenceIdentifier
                    ),
                    input: inputValue,
                    output: outputValue,
                    inferenceRealization: binding.realization,
                    usage: execution.usage,
                    route: execution.route,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    ),
                    metadata: execution.metadata
                )
            )

            return execution.output
        } catch {
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .inference(
                        site: site,
                        inference: Inference.definition.identifier
                    ),
                    input: inputValue,
                    inferenceRealization: appliedRealization,
                    failure: .init(
                        error: error
                    ),
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            throw error
        }
    }
}

struct AgentProgramRecordingToolInvoker:
    AgentProgramToolInvoking
{
    let executor: any AgentProgramToolExecuting
    let trace: AgentProgramExecutionTrace

    func invoke<Input, Output>(
        _ identifier: AgentToolIdentifier,
        input: Input,
        as output: Output.Type
    ) async throws -> Output
    where
        Input: Encodable & Sendable,
        Output: Decodable & Sendable
    {
        let inputValue = try JSONToolBridge.encode(
            input
        )
        let index = await trace.reserveIndex()
        let startedAt = Date()
        var outputValue: JSONValue?

        do {
            outputValue = try await executor.invoke(
                identifier,
                input: inputValue
            )
            let decoded = try JSONToolBridge.decode(
                Output.self,
                from: outputValue!
            )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .tool(
                        identifier
                    ),
                    input: inputValue,
                    output: outputValue,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            return decoded
        } catch {
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .tool(
                        identifier
                    ),
                    input: inputValue,
                    output: outputValue,
                    failure: .init(
                        error: error
                    ),
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            throw error
        }
    }
}

struct AgentProgramRecordingProgramInvoker:
    AgentProgramInvoking
{
    let invoker: any AgentProgramInvoking
    let trace: AgentProgramExecutionTrace

    func invoke<Program: AgentProgram>(
        _ program: Program.Type,
        input: Program.Input
    ) async throws -> Program.Output {
        let inputValue = try JSONToolBridge.encode(
            input
        )
        let index = await trace.reserveIndex()
        let startedAt = Date()

        do {
            let output = try await invoker.invoke(
                program,
                input: input
            )
            let outputValue = try JSONToolBridge.encode(
                output
            )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .program(
                        Program.descriptor.identifier
                    ),
                    input: inputValue,
                    output: outputValue,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            return output
        } catch {
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .program(
                        Program.descriptor.identifier
                    ),
                    input: inputValue,
                    failure: .init(
                        error: error
                    ),
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            throw error
        }
    }
}
