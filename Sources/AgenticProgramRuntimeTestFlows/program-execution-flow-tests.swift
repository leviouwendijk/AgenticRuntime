import Agentic
import AgenticInference
import AgenticPrograms
import AgenticRuntime
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runRuntimeServicesComposition()
        async throws
        -> [TestFlowDiagnostic]
    {
        let services = AgentRuntimeServices(
            model: .init(
                invoker: FixtureRuntimeServicesModelInvoker(),
                selection: .reviewer
            ),
            program: .init(
                tools: FixtureProgramToolExecutor()
            ),
            metadata: [
                "fixture_services": "shared",
            ]
        )
        let runner = AgentProgramRunner(
            services: services
        )
        let execution = try await runner.execute(
            FixtureProgram(),
            input: .init(
                value: "services",
                shouldFail: false
            )
        )

        try Expect.equal(
            execution.output,
            FixtureOutput(
                value: "tool:services"
            ),
            "Program execution consumes its capability projection from AgentRuntimeServices"
        )
        try Expect.equal(
            services.model?.selection,
            AgentModelSelection.reviewer,
            "the same Runtime services value retains a strong model invocation projection"
        )
        try Expect.equal(
            services.program.tools != nil,
            true,
            "the common Runtime services value carries Program tool execution capability"
        )
        try Expect.equal(
            services.metadata["fixture_services"],
            "shared",
            "common Runtime service metadata survives Program execution composition"
        )

        return [
            .field(
                "model_purpose",
                services.model?.selection.purpose.rawValue ?? "<none>"
            ),
            .field(
                "program_tools",
                String(services.program.tools != nil)
            ),
            .field(
                "output",
                execution.output?.value ?? "<none>"
            ),
        ]
    }

    static func runProgramExecutionRecord()
        async throws
        -> [TestFlowDiagnostic]
    {
        let runner = AgentProgramRunner(
            services: .init(
                program: .init(
                    tools: FixtureProgramToolExecutor()
                )
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
            from: step.output ?? .null
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
                program: .init(
                    tools: FixtureProgramToolExecutor()
                )
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
            inferences: try AgentProgramInferenceBindings(
                [
                    .init(
                        site: "fixture.inference-site",
                        inference: FixtureInference.definition.identifier,
                        realization: inferenceRealization
                    ),
                ]
            )
        )
        let runner = AgentProgramRunner(
            services: .init(
                program: .init(
                    inference: FixtureProgramInferenceExecutor()
                )
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
            step.inference.realization,
            inferenceRealization,
            "inference step preserves the exact applied realization"
        )
        let inferenceExecution = try Expect.notNil(
            step.inference.execution,
            "inference step preserves canonical inference execution evidence"
        )
        let attempt = try Expect.notNil(
            inferenceExecution.attempts.first,
            "canonical inference execution preserves its attempt"
        )

        try Expect.equal(
            inferenceExecution.inference,
            FixtureInference.definition.identifier,
            "canonical execution record preserves semantic inference identity"
        )
        try Expect.equal(
            inferenceExecution.strategy,
            inferenceRealization.strategy,
            "canonical execution record preserves strategy identity"
        )
        try Expect.equal(
            inferenceExecution.attempts.count,
            1,
            "canonical execution record preserves attempt count"
        )
        try Expect.equal(
            attempt.usage?.inputTokens,
            3,
            "canonical attempt preserves provider input usage"
        )
        try Expect.equal(
            attempt.usage?.outputTokens,
            2,
            "canonical attempt preserves provider output usage"
        )
        try Expect.equal(
            attempt.usage?.totalTokens,
            5,
            "canonical attempt preserves total provider usage"
        )
        try Expect.equal(
            inferenceExecution.metadata["fixture_executor"],
            "recorded",
            "inference executor metadata remains on canonical inference evidence"
        )

        let missingBindingExecution = try await runner.execute(
            FixtureInferenceProgram(),
            input: .init(
                value: "missing"
            ),
            realization: AgentProgramRealization<FixtureInferenceProgram>(
                id: "fixture.inference-program-missing-binding"
            )
        )
        let missingBindingFailure = try Expect.notNil(
            missingBindingExecution.record.failure,
            "missing inference binding fails the Program execution"
        )
        let missingBindingStep = try Expect.notNil(
            missingBindingExecution.record.steps.first,
            "missing inference binding remains visible as a failed semantic step"
        )
        let missingBindingStepFailure = try Expect.notNil(
            missingBindingStep.failure,
            "failed binding step records its canonical error"
        )

        try Expect.equal(
            missingBindingExecution.record.outcome,
            .failed,
            "missing Program inference binding produces a failed execution"
        )
        try Expect.equal(
            missingBindingFailure.type,
            String(
                reflecting: AgentProgramInferenceInvocationError.self
            ),
            "Runtime propagates the canonical AgenticPrograms binding error"
        )
        try Expect.equal(
            missingBindingStepFailure.type,
            String(
                reflecting: AgentProgramInferenceInvocationError.self
            ),
            "Runtime step recording preserves the canonical AgenticPrograms binding error"
        )
        try Expect.equal(
            missingBindingStep.inference.realization == nil,
            true,
            "an invalid binding is never recorded as an applied inference realization"
        )
        try Expect.equal(
            missingBindingStep.inference.execution == nil,
            true,
            "binding failure produces no canonical inference execution evidence"
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
                step.inference.realization?.strategy.rawValue ?? "<none>"
            ),
            .field(
                "usage",
                String(attempt.usage?.totalTokens ?? 0)
            ),
            .field(
                "missing_binding_failure",
                missingBindingFailure.type
            ),
        ]
    }
}

private enum FixtureRuntimeServicesModelError:
    Error,
    Sendable
{
    case unexpectedInvocation
}

private struct FixtureRuntimeServicesModelInvoker:
    AgentModelInvoking
{
    func buffered(
        _ invocation: AgentModelInvocation
    ) async throws -> AgentModelInvocationResult {
        throw FixtureRuntimeServicesModelError.unexpectedInvocation
    }

    func stream(
        _ invocation: AgentModelInvocation
    ) -> AsyncThrowingStream<AgentModelInvocationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: FixtureRuntimeServicesModelError.unexpectedInvocation
            )
        }
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
    ) async throws -> AgentToolExecutionResult {
        if identifier.rawValue == "fixture.fail" {
            throw FixtureProgramToolError.requestedFailure
        }

        let decoded = try JSONToolBridge.decode(
            FixtureToolInput.self,
            from: input
        )

        return AgentToolExecutionResult(
            result: AgentToolResult(
                toolCallID: "fixture-\(identifier.rawValue)",
                name: identifier.rawValue,
                output: try JSONToolBridge.encode(
                    FixtureOutput(
                        value: "tool:\(decoded.value)"
                    )
                ),
                isError: false
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
    AgentInferenceExecuting
{
    func execute<Inference: AgentInference>(
        _ inference: Inference.Type,
        input: Inference.Input,
        realization: AgentInferenceRealization
    ) async throws -> AgentInferenceExecutionResult<Inference.Output> {
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

        let usage = AgentUsage(
            inputTokens: 3,
            outputTokens: 2,
            totalTokens: 5
        )
        let selection = realization.modelSelection
        let profile = AgentModelProfile(
            identifier: "fixture.inference.profile",
            gatewayIdentifier: "fixture.inference.gateway",
            model: "fixture",
            purposes: [
                selection.purpose,
            ],
            capabilities: [
                .text,
                .structured_output,
            ]
        )
        let route = AgentModelRouteRecord(
            route: AgentModelRoute(
                purpose: selection.purpose,
                profile: profile
            ),
            requestMetadata: [:],
            responseMetadata: [:],
            usage: usage
        )
        let attempt = AgentInferenceAttemptRecord(
            index: 0,
            adapter: AgentInferenceAdapterIdentifier(
                rawValue: "fixture.inference.adapter"
            ),
            selection: selection,
            route: route,
            usage: usage,
            metadata: [
                "fixture_executor": "recorded",
            ]
        )

        return .init(
            output: output,
            record: AgentInferenceExecutionRecord(
                inference: Inference.definition.identifier,
                strategy: realization.strategy,
                attempts: [
                    attempt,
                ],
                budget: realization.budget,
                metadata: [
                    "fixture_executor": "recorded",
                    "strategy": realization.strategy.rawValue,
                ]
            )
        )
    }
}
