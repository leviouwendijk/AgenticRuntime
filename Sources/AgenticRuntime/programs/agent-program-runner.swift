import Agentic
import AgenticExecution
import AgenticPrograms
import Foundation
import Primitives

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
        sessionID: String? = nil,
        metadata: [String: String] = [:]
    ) async throws -> AgentProgramExecution<Program> {
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

    public func resume<Program: AgentProgram>(
        _ program: Program,
        from checkpoint: AgentProgramCheckpoint,
        interaction response: AgentInteraction.Response
    ) async throws -> AgentProgramExecution<Program> {
        let resume = try AgentProgramCheckpoint.Resume<Program>(
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

    private func run<Program: AgentProgram>(
        _ program: Program,
        input: Program.Input,
        realization: AgentProgramRealization<Program>?,
        sessionID: String,
        metadata: [String: String],
        resume: AgentProgramCheckpoint.Resume<Program>?
    ) async throws -> AgentProgramExecution<Program> {
        let inputValue = try JSONToolBridge.encode(input)
        let realizationValue: JSONValue?

        if let realization {
            realizationValue = try JSONToolBridge.encode(realization)
        } else {
            realizationValue = nil
        }

        let trace = AgentProgramExecutionTrace(
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
            AgentProgramResumeControl(resume: $0)
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
                trace: trace,
                resumeControl: resumeControl
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

            if let resumeControl {
                try await resumeControl.requireConsumed()
            }

            let outputValue = try JSONToolBridge.encode(output)
            let completedAt = Date()
            let steps = await trace.snapshot()
            let record = AgentProgramExecutionRecord(
                sessionID: sessionID,
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
        } catch let signal as AgentProgramSuspensionSignal {
            let completedAt = Date()
            let steps = await trace.snapshot()

            guard let suspendedStep = steps.first(
                where: { step in
                    step.suspension?.id == signal.suspension.id
                }
            ) else {
                throw AgentProgramReplayError.step_mismatch(
                    index: steps.count
                )
            }

            let checkpoint = AgentProgramCheckpoint(
                sessionID: sessionID,
                programIdentifier: Program.descriptor.identifier,
                programVersion: Program.descriptor.version,
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
            let record = AgentProgramExecutionRecord(
                sessionID: sessionID,
                programIdentifier: Program.descriptor.identifier,
                programVersion: Program.descriptor.version,
                realizationIdentifier: realization?.id,
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
            let record = AgentProgramExecutionRecord(
                sessionID: sessionID,
                programIdentifier: Program.descriptor.identifier,
                programVersion: Program.descriptor.version,
                realizationIdentifier: realization?.id,
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
