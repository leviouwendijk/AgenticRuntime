import Agentic
import AgenticPrograms
import AgenticRuntime
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runProgramExecutionRecord()
        async throws
        -> [TestFlowDiagnostic]
    {
        let runner = AgentProgramRunner(
            services: .init(
                tools: FixtureProgramToolExecutor()
            )
        )
        let execution = try await runner.execute(
            FixtureProgram(),
            input: .init(
                value: "hello",
                shouldFail: false
            )
        )

        try Expect.equal(
            execution.output,
            FixtureOutput(
                value: "tool:hello"
            ),
            "program runtime preserves typed output"
        )
        try Expect.equal(
            execution.record.outcome,
            .succeeded,
            "successful program execution is recorded"
        )
        try Expect.equal(
            execution.record.programIdentifier,
            FixtureProgram.descriptor.identifier,
            "execution record preserves program identity"
        )
        try Expect.equal(
            execution.record.steps.count,
            1,
            "tool invocation becomes one execution step"
        )

        let step = execution.record.steps[0]
        let toolIdentifier: AgentToolIdentifier?
        if case .tool(let identifier) = step.kind {
            toolIdentifier = identifier
        } else {
            toolIdentifier = nil
        }

        try Expect.equal(
            toolIdentifier,
            AgentToolIdentifier(
                "fixture.echo"
            ),
            "step preserves tool identity"
        )
        try Expect.equal(
            step.failure == nil,
            true,
            "successful step has no failure"
        )

        let stepInput = try JSONToolBridge.decode(
            FixtureToolInput.self,
            from: step.input
        )
        let stepOutput = try JSONToolBridge.decode(
            FixtureOutput.self,
            from: step.output!
        )

        try Expect.equal(
            stepInput.value,
            "hello",
            "step captures exact tool input"
        )
        try Expect.equal(
            stepOutput.value,
            "tool:hello",
            "step captures exact tool output"
        )

        return [
            .field(
                "program",
                execution.record.programIdentifier.rawValue
            ),
            .field(
                "outcome",
                execution.record.outcome.rawValue
            ),
            .field(
                "steps",
                String(execution.record.steps.count)
            ),
            .field(
                "output",
                execution.output?.value ?? "<none>"
            ),
        ]
    }

    static func runProgramExecutionFailureRecord()
        async throws
        -> [TestFlowDiagnostic]
    {
        let runner = AgentProgramRunner(
            services: .init(
                tools: FixtureProgramToolExecutor()
            )
        )
        let execution = try await runner.execute(
            FixtureProgram(),
            input: .init(
                value: "failure",
                shouldFail: true
            )
        )

        try Expect.equal(
            execution.output == nil,
            true,
            "failed program execution has no typed output"
        )
        try Expect.equal(
            execution.record.outcome,
            .failed,
            "failed program execution remains a structured record"
        )
        try Expect.equal(
            execution.record.failure != nil,
            true,
            "root execution preserves failure"
        )
        try Expect.equal(
            execution.record.steps.count,
            1,
            "failed tool invocation remains in step trace"
        )
        try Expect.equal(
            execution.record.steps[0].failure != nil,
            true,
            "failed step preserves failure"
        )
        try Expect.equal(
            execution.record.steps[0].output == nil,
            true,
            "failed fixture tool has no output"
        )

        return [
            .field(
                "outcome",
                execution.record.outcome.rawValue
            ),
            .field(
                "steps",
                String(execution.record.steps.count)
            ),
            .field(
                "failure",
                execution.record.failure?.message ?? "<none>"
            ),
        ]
    }

    static func runProgramInferenceExecutionRecord()
        async throws
        -> [TestFlowDiagnostic]
    {
        let inferenceRealization = AgentInferenceRealization(
            strategy: "fixture.direct",
            modelSelection: .executor,
            instructions: "Produce the fixture inference output.",
            budget: .singleAttempt
        )
        let programRealization = AgentProgramRealization<FixtureInferenceProgram>(
            id: "fixture.inference-program-realization",
            inferences: [
                .init(
                    site: "fixture.inference-site",
                    inference: FixtureInference.definition.identifier,
                    realization: inferenceRealization
                ),
            ]
        )
        let runner = AgentProgramRunner(
            services: .init(
                inference: FixtureProgramInferenceExecutor()
            )
        )
        let execution = try await runner.execute(
            FixtureInferenceProgram(),
            input: .init(
                value: "hello"
            ),
            realization: programRealization
        )

        try Expect.equal(
            execution.output,
            .string("inferred:hello"),
            "program receives the typed inference output"
        )
        try Expect.equal(
            execution.record.outcome,
            .succeeded,
            "inference-backed program succeeds"
        )
        try Expect.equal(
            execution.record.realizationIdentifier,
            programRealization.id,
            "root execution preserves realization identity"
        )
        try Expect.equal(
            execution.record.steps.count,
            1,
            "one semantic inference becomes one program step"
        )

        let step = execution.record.steps[0]
        let inferenceSite: AgentInferenceSiteIdentifier?
        let inferenceIdentifier: AgentInferenceIdentifier?

        if case .inference(
            let site,
            let inference
        ) = step.kind {
            inferenceSite = site
            inferenceIdentifier = inference
        } else {
            inferenceSite = nil
            inferenceIdentifier = nil
        }

        try Expect.equal(
            inferenceSite,
            AgentInferenceSiteIdentifier(
                "fixture.inference-site"
            ),
            "inference step preserves stable site identity"
        )
        try Expect.equal(
            inferenceIdentifier,
            FixtureInference.definition.identifier,
            "inference step preserves semantic inference identity"
        )
        try Expect.equal(
            step.inferenceRealization,
            inferenceRealization,
            "inference step preserves the exact applied realization"
        )
        try Expect.equal(
            step.usage?.inputTokens,
            3,
            "inference step preserves provider input usage"
        )
        try Expect.equal(
            step.usage?.outputTokens,
            2,
            "inference step preserves provider output usage"
        )
        try Expect.equal(
            step.usage?.totalTokens,
            5,
            "inference step preserves total provider usage"
        )
        try Expect.equal(
            step.metadata["fixture_executor"],
            "recorded",
            "inference executor metadata survives on the step"
        )
        try Expect.equal(
            step.route == nil,
            true,
            "non-broker fixture may omit a model route"
        )

        return [
            .field(
                "program",
                execution.record.programIdentifier.rawValue
            ),
            .field(
                "site",
                inferenceSite?.rawValue ?? "<none>"
            ),
            .field(
                "strategy",
                step.inferenceRealization?.strategy.rawValue ?? "<none>"
            ),
            .field(
                "usage",
                String(step.usage?.totalTokens ?? 0)
            ),
        ]
    }
}

private struct FixtureInput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
    let shouldFail: Bool
}

private struct FixtureToolInput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct FixtureOutput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private struct FixtureProgram: AgentProgram {
    typealias Input = FixtureInput
    typealias Output = FixtureOutput

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.runtime",
        title: "Runtime fixture",
        summary: "Exercises Runtime-owned program execution recording.",
        version: "1"
    )

    func run(
        _ input: FixtureInput,
        in context: AgentProgramContext
    ) async throws -> FixtureOutput {
        try await context.invoke(
            input.shouldFail
                ? "fixture.fail"
                : "fixture.echo",
            input: FixtureToolInput(
                value: input.value
            ),
            as: FixtureOutput.self
        )
    }
}

private enum FixtureProgramToolError:
    Error,
    Sendable
{
    case requestedFailure
}

private struct FixtureProgramToolExecutor:
    AgentProgramToolExecuting
{
    func invoke(
        _ identifier: AgentToolIdentifier,
        input: JSONValue
    ) async throws -> JSONValue {
        if identifier.rawValue == "fixture.fail" {
            throw FixtureProgramToolError.requestedFailure
        }

        let decoded = try JSONToolBridge.decode(
            FixtureToolInput.self,
            from: input
        )

        return try JSONToolBridge.encode(
            FixtureOutput(
                value: "tool:\(decoded.value)"
            )
        )
    }
}

private struct FixtureInferenceInput:
    Sendable,
    Codable,
    Hashable
{
    let value: String
}

private enum FixtureInference: AgentInference {
    typealias Input = FixtureInferenceInput
    typealias Output = JSONValue

    static let definition = AgentInferenceDefinition(
        identifier: "fixture.inference",
        purpose: "Produce deterministic fixture inference output."
    )
}

private struct FixtureInferenceProgram: AgentProgram {
    typealias Input = FixtureInferenceInput
    typealias Output = JSONValue

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.inference-program",
        title: "Inference runtime fixture",
        summary: "Exercises realized inference execution recording.",
        version: "1"
    )

    func run(
        _ input: FixtureInferenceInput,
        in context: AgentProgramContext
    ) async throws -> JSONValue {
        try await context.infer(
            FixtureInference.self,
            at: "fixture.inference-site",
            input: input
        )
    }
}

private struct FixtureProgramInferenceExecutor:
    AgentProgramInferenceExecuting
{
    func infer<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentProgramInferenceExecution<Inference.Output> {
        let encodedInput = try JSONToolBridge.encode(
            input
        )
        let fixtureInput = try JSONToolBridge.decode(
            FixtureInferenceInput.self,
            from: encodedInput
        )
        let encodedOutput = JSONValue.string(
            "inferred:\(fixtureInput.value)"
        )
        let output = try JSONToolBridge.decode(
            Inference.Output.self,
            from: encodedOutput
        )

        return .init(
            output: output,
            usage: .init(
                inputTokens: 3,
                outputTokens: 2,
                totalTokens: 5
            ),
            metadata: [
                "fixture_executor": "recorded",
                "strategy": realization.strategy.rawValue,
            ]
        )
    }
}
