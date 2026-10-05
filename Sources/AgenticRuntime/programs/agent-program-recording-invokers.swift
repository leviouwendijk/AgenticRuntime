import Agentic
import Foundation
import Primitives

actor ProgramExecutionTrace {
    private var nextIndex = 0
    private var records: [ProgramStepRecord] = []
    private let replaySteps: [ProgramStepRecord]
    private let expectedSuspendedStep: ProgramStepRecord?

    init(
        replaySteps: [ProgramStepRecord] = [],
        expectedSuspendedStep: ProgramStepRecord? = nil
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
        kind: ProgramStepKind,
        input: JSONValue
    ) throws -> ProgramStepRecord? {
        if index < replaySteps.count {
            let record = replaySteps[index]

            guard record.index == index,
                  record.kind == kind,
                  record.input == input,
                  record.isReplayableCompletedStep
            else {
                throw ProgramReplayError.step_mismatch(
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
                throw ProgramReplayError.step_mismatch(
                    index: index
                )
            }
        }

        return nil
    }

    func append(
        _ record: ProgramStepRecord
    ) {
        records.append(record)
    }

    func snapshot() -> [ProgramStepRecord] {
        records.sorted {
            $0.index < $1.index
        }
    }
}

struct ProgramRecordingInferenceInvoker<ProgramType: Program>:
    InferenceInvoking
{
    let executor: any InferenceExecuting
    let realization: ProgramRealization<ProgramType>?
    let trace: ProgramExecutionTrace

    func infer<
        SiteProgramType: Program,
        InferenceType: Inference
    >(
        _ site: InferenceSite<SiteProgramType, InferenceType>,
        input: InferenceType.Input
    ) async throws -> InferenceType.Output {
        guard site.program == ProgramType.definition.identifier else {
            throw ProgramInferenceInvocationError.programMismatch(
                site: site.identifier,
                expected: ProgramType.definition.identifier,
                received: site.program
            )
        }

        let ownedSite = InferenceSite<ProgramType, InferenceType>(
            identifier: site.identifier
        )
        let inputValue = try JSONCoding.default.value(input)
        let index = await trace.reserveIndex()
        let startedAt = Date()
        var appliedRealization: InferenceRealizationConfiguration?

        do {
            let invocation = try ProgramInferenceInvocation(
                ownedSite,
                in: realization
            )
            let inferenceIdentifier = invocation.inference
            appliedRealization = invocation.configuration

            if let replayed = try await trace.replay(
                index: index,
                kind: .inference(
                    site: site.identifier,
                    inference: inferenceIdentifier
                ),
                input: inputValue
            ) {
                guard replayed.inference.realization
                        == invocation.configuration,
                      let outputValue = replayed.output
                else {
                    throw ProgramReplayError.step_mismatch(
                        index: index
                    )
                }

                let output = try JSONCoding.default.decode(
                    InferenceType.Output.self,
                    from: outputValue
                )

                await trace.append(replayed)
                return output
            }

            let execution = try await invocation.execute(
                input: input,
                using: executor
            )
            let outputValue = try JSONCoding.default.value(
                execution.output
            )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .inference(
                        site: site.identifier,
                        inference: inferenceIdentifier
                    ),
                    input: inputValue,
                    output: outputValue,
                    inference: .init(
                        realization: invocation.configuration,
                        execution: execution.record
                    ),
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            return execution.output
        } catch let error as ProgramInferenceFailure {
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .inference(
                        site: site.identifier,
                        inference: InferenceType.definition.identifier
                    ),
                    input: inputValue,
                    inference: .init(
                        realization: appliedRealization,
                        execution: error.execution?.record
                    ),
                    recovery: error.recovery,
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
                    kind: .inference(
                        site: site.identifier,
                        inference: InferenceType.definition.identifier
                    ),
                    input: inputValue,
                    inference: .init(
                        realization: appliedRealization
                    ),
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

struct ProgramRecordingToolInvoker:
    ProgramToolInvoking
{
    let executor: any ProgramToolExecuting
    let trace: ProgramExecutionTrace
    let resumeControl: ProgramResumeControl?

    func invoke<Input, Output>(
        _ identifier: ToolIdentifier,
        input: Input,
        as output: Output.Type
    ) async throws -> Output
    where
        Input: Encodable & Sendable,
        Output: Decodable & Sendable
    {
        let inputValue = try JSONCoding.default.value(input)
        let index = await trace.reserveIndex()

        if let replayed = try await trace.replay(
            index: index,
            kind: .tool(identifier),
            input: inputValue
        ) {
            if let failure = replayed.replayableToolFailure {
                await trace.append(replayed)
                throw failure
            }

            guard let replayedOutput = replayed.output,
                  replayed.failure == nil
            else {
                throw ProgramReplayError.invalid_completed_step(
                    index: index
                )
            }

            let decoded = try JSONCoding.default.decode(
                Output.self,
                from: replayedOutput
            )

            await trace.append(replayed)
            return decoded
        }

        let startedAt = Date()
        var outputValue: JSONValue?
        var recovery: Recovery.Record?

        do {
            let execution: ToolExecutionResult

            if let resumeControl,
               let resolution = try await resumeControl.resolution(
                   at: index,
                   identifier: identifier,
                   input: inputValue
               )
            {
                execution = try await executor.resume(
                    pendingApproval: resolution.pendingApproval,
                    decision: resolution.decision
                )
            } else {
                execution = try await executor.invoke(
                    identifier,
                    input: inputValue
                )
            }

            outputValue = execution.result.output
            recovery = execution.recovery

            let decoded = try JSONCoding.default.decode(
                Output.self,
                from: execution.result.output
            )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .tool(identifier),
                    input: inputValue,
                    output: execution.result.output,
                    toolResult: execution.result,
                    recovery: execution.recovery,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            return decoded
        } catch let signal as ProgramSuspensionSignal {
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
        } catch let error as ProgramToolFailure {
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .tool(identifier),
                    input: inputValue,
                    output: outputValue,
                    toolResult: error.result,
                    recovery: error.recovery,
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
                    kind: .tool(identifier),
                    input: inputValue,
                    output: outputValue,
                    recovery: recovery,
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

struct ProgramRecordingProgramInvoker:
    ProgramInvoking
{
    let invoker: any ProgramInvoking
    let trace: ProgramExecutionTrace

    func invoke<ProgramType: Program>(
        _ program: ProgramType.Type,
        input: ProgramType.Input,
        in context: ProgramContext
    ) async throws -> ProgramType.Output {
        let inputValue = try JSONCoding.default.value(input)
        let index = await trace.reserveIndex()
        let startedAt = Date()

        do {
            if let replayed = try await trace.replay(
                index: index,
                kind: .program(ProgramType.definition.identifier),
                input: inputValue
            ) {
                guard let outputValue = replayed.output else {
                    throw ProgramReplayError.invalid_completed_step(
                        index: index
                    )
                }

                let output = try JSONCoding.default.decode(
                    ProgramType.Output.self,
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
            let outputValue = try JSONCoding.default.value(output)
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .program(ProgramType.definition.identifier),
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
        } catch is ProgramSuspensionSignal {
            let error = ProgramReplayError
                .nested_program_suspension_unsupported(
                    ProgramType.definition.identifier
                )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .program(ProgramType.definition.identifier),
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
                    kind: .program(ProgramType.definition.identifier),
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
