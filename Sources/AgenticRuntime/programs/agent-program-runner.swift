import Agentic
import AgenticExecution
import Foundation
import Primitives

public struct ProgramRunner: Sendable {
    public var services: AgentRuntimeServices

    public init(
        services: AgentRuntimeServices = .init()
    ) {
        self.services = services
    }

    public func execute<ProgramType: Program>(
        _ program: ProgramType,
        input: ProgramType.Input,
        realization: ProgramRealization<ProgramType>? = nil,
        sessionID: String? = nil,
        metadata: [String: String] = [:]
    ) async throws -> ProgramExecution<ProgramType> {
        try await run(
            program,
            input: input,
            realization: realization,
            sessionID: sessionID
                ?? "program-\(UUID().uuidString)",
            metadata: metadata,
            resume: nil
        )
    }

    public func resume<ProgramType: Program>(
        _ program: ProgramType,
        from checkpoint: ProgramCheckpoint,
        interaction response: AgentInteraction.Response
    ) async throws -> ProgramExecution<ProgramType> {
        let resume = try ProgramCheckpoint.Resume<ProgramType>(
            checkpoint: checkpoint,
            response: response
        )

        return try await run(
            program,
            input: resume.input,
            realization: resume.realization,
            sessionID: resume.sessionID,
            metadata: resume.metadata,
            resume: resume
        )
    }

    private func run<ProgramType: Program>(
        _ program: ProgramType,
        input: ProgramType.Input,
        realization: ProgramRealization<ProgramType>?,
        sessionID: String,
        metadata: [String: String],
        resume: ProgramCheckpoint.Resume<ProgramType>?
    ) async throws -> ProgramExecution<ProgramType> {
        let inputValue = try JSONToolBridge.encode(input)
        let realizationValue: JSONValue?

        if let realization {
            realizationValue = try JSONToolBridge.encode(realization)
        } else {
            realizationValue = nil
        }

        let trace = ProgramExecutionTrace(
            replaySteps: resume?.completedSteps ?? [],
            expectedSuspendedStep: resume?.suspendedStep
        )
        let startedAt = resume?.startedAt ?? Date()
        let executionMetadata = services.metadata.merging(
            metadata
        ) { _, new in
            new
        }
        let resumeControl = resume.map {
            ProgramResumeControl(resume: $0)
        }
        let userInputInvoker = ProgramRecordingUserInputInvoker(
            trace: trace,
            resumeControl: resumeControl
        )

        let inferenceInvoker: (any InferenceInvoking)?
        if let inferenceExecutor = services.program.inference {
            inferenceInvoker = ProgramRecordingInferenceInvoker<ProgramType>(
                executor: inferenceExecutor,
                realization: realization,
                trace: trace
            )
        } else {
            inferenceInvoker = nil
        }

        let toolInvoker: (any ProgramToolInvoking)?
        if let toolExecutor = services.program.tools {
            toolInvoker = ProgramRecordingToolInvoker(
                executor: toolExecutor,
                trace: trace,
                resumeControl: resumeControl
            )
        } else {
            toolInvoker = nil
        }

        let programInvoker: (any ProgramInvoking)?
        if let nestedProgramInvoker = services.program.invoker {
            programInvoker = ProgramRecordingProgramInvoker(
                invoker: nestedProgramInvoker,
                trace: trace
            )
        } else {
            programInvoker = nil
        }

        let context = ProgramContext(
            inference: inferenceInvoker,
            tools: toolInvoker,
            programs: programInvoker,
            userInput: userInputInvoker,
            artifacts: services.artifacts,
            metadata: executionMetadata
        )

        do {
            let output = try await program.run(
                input,
                in: context
            )

            if let resumeControl {
                try await resumeControl.requireConsumed()
            }

            let outputValue = try JSONToolBridge.encode(output)
            let completedAt = Date()
            let steps = await trace.snapshot()
            let record = ProgramExecutionRecord(
                sessionID: sessionID,
                programIdentifier: ProgramType.definition.identifier,
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
        } catch let signal as ProgramSuspensionSignal {
            let completedAt = Date()
            let steps = await trace.snapshot()

            guard let suspendedStep = steps.first(
                where: { step in
                    step.suspension?.id == signal.suspension.id
                }
            ) else {
                throw ProgramReplayError.step_mismatch(
                    index: steps.count
                )
            }

            let checkpoint = ProgramCheckpoint(
                sessionID: sessionID,
                programIdentifier: ProgramType.definition.identifier,
                input: inputValue,
                realization: realizationValue,
                completedSteps: steps.filter { step in
                    step.index < suspendedStep.index
                },
                suspendedStep: suspendedStep,
                suspension: signal.suspension,
                startedAt: startedAt,
                metadata: executionMetadata
            )
            let record = ProgramExecutionRecord(
                sessionID: sessionID,
                programIdentifier: ProgramType.definition.identifier,
                input: inputValue,
                steps: steps,
                outcome: .suspended,
                suspension: signal.suspension,
                checkpoint: checkpoint,
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
        } catch {
            let completedAt = Date()
            let steps = await trace.snapshot()
            let record = ProgramExecutionRecord(
                sessionID: sessionID,
                programIdentifier: ProgramType.definition.identifier,
                input: inputValue,
                steps: steps,
                outcome: .failed,
                failure: .init(error: error),
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
