import Agentic
import AgenticInference
import AgenticPrograms
import Foundation
import Primitives

actor AgentProgramExecutionTrace {
    private var nextIndex = 0
    private var records: [AgentProgramStepRecord] = []
    private let replaySteps: [AgentProgramStepRecord]
    private let expectedSuspendedStep: AgentProgramStepRecord?

    init(
        replaySteps: [AgentProgramStepRecord] = [],
        expectedSuspendedStep: AgentProgramStepRecord? = nil
    ) {
        self.replaySteps = replaySteps
        self.expectedSuspendedStep = expectedSuspendedStep
    }

    func reserveIndex() -> Int {
        let index = nextIndex
        nextIndex += 1
        return index
    }

    func replay(
        index: Int,
        kind: AgentProgramStepKind,
        input: JSONValue
    ) throws -> AgentProgramStepRecord? {
        if index < replaySteps.count {
            let record = replaySteps[index]

            guard record.index == index,
                  record.kind == kind,
                  record.input == input,
                  record.output != nil,
                  record.suspension == nil,
                  record.failure == nil
            else {
                throw AgentProgramReplayError.step_mismatch(
                    index: index
                )
            }

            return record
        }

        if let expectedSuspendedStep,
           index == expectedSuspendedStep.index
        {
            guard expectedSuspendedStep.kind == kind,
                  expectedSuspendedStep.input == input
            else {
                throw AgentProgramReplayError.step_mismatch(
                    index: index
                )
            }
        }

        return nil
    }

    func append(
        _ record: AgentProgramStepRecord
    ) {
        records.append(record)
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
        let inputValue = try JSONToolBridge.encode(input)
        let index = await trace.reserveIndex()
        let startedAt = Date()
        var appliedRealization: AgentInferenceRealization?

        do {
            let inferenceIdentifier = Inference.definition.identifier

            guard let binding = realization?.inference(at: site) else {
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

            if let replayed = try await trace.replay(
                index: index,
                kind: .inference(
                    site: site,
                    inference: inferenceIdentifier
                ),
                input: inputValue
            ) {
                guard replayed.inferenceRealization
                        == binding.realization,
                      let outputValue = replayed.output
                else {
                    throw AgentProgramReplayError.step_mismatch(
                        index: index
                    )
                }

                let output = try JSONToolBridge.decode(
                    Inference.Output.self,
                    from: outputValue
                )

                await trace.append(replayed)
                return output
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
                    failure: .init(error: error),
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
    let resumeControl: AgentProgramResumeControl?

    func invoke<Input, Output>(
        _ identifier: AgentToolIdentifier,
        input: Input,
        as output: Output.Type
    ) async throws -> Output
    where
        Input: Encodable & Sendable,
        Output: Decodable & Sendable
    {
        let inputValue = try JSONToolBridge.encode(input)
        let index = await trace.reserveIndex()
        let startedAt = Date()
        var outputValue: JSONValue?

        do {
            if let replayed = try await trace.replay(
                index: index,
                kind: .tool(identifier),
                input: inputValue
            ) {
                guard let replayedOutput = replayed.output else {
                    throw AgentProgramReplayError.invalid_completed_step(
                        index: index
                    )
                }

                let decoded = try JSONToolBridge.decode(
                    Output.self,
                    from: replayedOutput
                )

                await trace.append(replayed)
                return decoded
            }

            let resolvedOutput: JSONValue

            if let resumeControl,
               let resolution = try await resumeControl.resolution(
                   at: index,
                   identifier: identifier,
                   input: inputValue
               )
            {
                resolvedOutput = try await executor.resume(
                    pendingApproval: resolution.pendingApproval,
                    decision: resolution.decision
                )
            } else {
                resolvedOutput = try await executor.invoke(
                    identifier,
                    input: inputValue
                )
            }

            outputValue = resolvedOutput

            let decoded = try JSONToolBridge.decode(
                Output.self,
                from: resolvedOutput
            )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .tool(identifier),
                    input: inputValue,
                    output: resolvedOutput,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            return decoded
        } catch let signal as AgentProgramSuspensionSignal {
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .tool(identifier),
                    input: inputValue,
                    output: outputValue,
                    suspension: signal.suspension,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            throw signal
        } catch {
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .tool(identifier),
                    input: inputValue,
                    output: outputValue,
                    failure: .init(error: error),
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
        input: Program.Input,
        in context: AgentProgramContext
    ) async throws -> Program.Output {
        let inputValue = try JSONToolBridge.encode(input)
        let index = await trace.reserveIndex()
        let startedAt = Date()

        do {
            if let replayed = try await trace.replay(
                index: index,
                kind: .program(Program.descriptor.identifier),
                input: inputValue
            ) {
                guard let outputValue = replayed.output else {
                    throw AgentProgramReplayError.invalid_completed_step(
                        index: index
                    )
                }

                let output = try JSONToolBridge.decode(
                    Program.Output.self,
                    from: outputValue
                )

                await trace.append(replayed)
                return output
            }

            let output = try await invoker.invoke(
                program,
                input: input,
                in: context
            )
            let outputValue = try JSONToolBridge.encode(output)
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .program(Program.descriptor.identifier),
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
        } catch is AgentProgramSuspensionSignal {
            let error = AgentProgramReplayError
                .nested_program_suspension_unsupported(
                    Program.descriptor.identifier
                )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .program(Program.descriptor.identifier),
                    input: inputValue,
                    failure: .init(error: error),
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            throw error
        } catch {
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .program(Program.descriptor.identifier),
                    input: inputValue,
                    failure: .init(error: error),
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
