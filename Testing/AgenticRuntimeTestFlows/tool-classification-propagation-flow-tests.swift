import Agentic
import AgenticRuntime
import Primitives
import Schema
import TestFlows
import Workspace

private enum ClassificationPropagationCallError: Error {
    case authorization_required
}

private enum ClassificationPropagationTestError: Error {
    case missing_recovery
}

private actor ClassificationPropagationProbe {
    private var calls = 0

    func recordCall() {
        calls += 1
    }

    func count() -> Int {
        calls
    }
}

private struct ClassificationPropagationInput:
    Sendable,
    Codable,
    JSONSchemaProviding
{
    static var jsonschema: JSONSchema {
        .object {}
    }
}

private struct ClassificationPropagationOutput:
    Sendable,
    Codable,
    Hashable,
    JSONSchemaProviding
{
    let resultIsError: Bool
    let kind: String
    let effect: String
    let retry: String
    let outcome: String
    let hasPlan: Bool
    let attempts: Int

    static var jsonschema: JSONSchema {
        .object(
            properties: [
                .init(
                    name: "resultIsError",
                    schema: .boolean(),
                    required: true
                ),
                .init(
                    name: "kind",
                    schema: .string(),
                    required: true
                ),
                .init(
                    name: "effect",
                    schema: .string(),
                    required: true
                ),
                .init(
                    name: "retry",
                    schema: .string(),
                    required: true
                ),
                .init(
                    name: "outcome",
                    schema: .string(),
                    required: true
                ),
                .init(
                    name: "hasPlan",
                    schema: .boolean(),
                    required: true
                ),
                .init(
                    name: "attempts",
                    schema: .integer(),
                    required: true
                ),
            ],
            additionalProperties: .disallowed
        )
    }
}

private struct ClassificationPropagationProgram:
    Program
{
    typealias Input = ClassificationPropagationInput
    typealias Output = ClassificationPropagationOutput

    static let definition = ProgramDefinition(
        identifier: "fixture.classification_propagation_program",
        purpose: "Proves a classified tool failure propagates through Runtime into authored Program handling without mechanical retry.",
        title: "Classification propagation fixture"
    )

    func run(
        _ input: Input,
        in context: ProgramContext
    ) async throws -> Output {
        try await context.invoke(
            "fixture.classification_propagation",
            input: input,
            as: Output.self
        ) { failure -> Output in
            guard let recovery = failure.recovery else {
                throw ClassificationPropagationTestError
                    .missing_recovery
            }

            return Output(
                resultIsError: failure.result.isError,
                kind: recovery.incident.kind.rawValue,
                effect: recovery.state.effect.rawValue,
                retry: recovery.state.retry.rawValue,
                outcome: recovery.outcome.rawValue,
                hasPlan: recovery.plan != nil,
                attempts: recovery.attempts.count
            )
        }
    }
}

private struct ClassificationPropagationTool: Tool {
    typealias Input = ClassificationPropagationInput
    typealias Output = ClassificationPropagationOutput

    let probe: ClassificationPropagationProbe

    let identifier: ToolIdentifier =
        "fixture.classification_propagation"
    let description =
        "Fixture proving classified tool evidence propagates without mechanical recovery."
    let risk: ActionRisk = .observe

    static let definition = ToolDefinition(
        identifier: "fixture.classification_propagation",
        purpose: "Fixture proving classified tool evidence propagates without mechanical recovery.",
        risk: .observe
    )

    func call(
        _ input: Input,
        in _: ToolContext
    ) async throws -> Output {
        _ = input
        await probe.recordCall()
        throw ClassificationPropagationCallError
            .authorization_required
    }

    func classify(
        _ error: any Error,
        phase: ToolCall.Phase,
        input _: Input?
    ) -> Recovery.Incident? {
        guard
            phase == .call,
            let error = error
                as? ClassificationPropagationCallError,
            case .authorization_required = error
        else {
            return nil
        }

        return Recovery.Incident(
            kind: .authorization_required,
            stage: .execution,
            effectState: .not_applied,
            retrySafety: .safe,
            scope: .init(
                kind: .tool,
                identifier: identifier.rawValue
            ),
            message: "fixture authorization failure occurred before any effect was applied"
        )
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runToolClassificationPropagation()
        async throws
        -> [TestDiagnostic]
    {
        let probe = ClassificationPropagationProbe()
        let registry = try ToolRegistry {
            ClassificationPropagationTool(
                probe: probe
            )
        }
        let runner = ProgramRunner(
            services: .init(
                program: .init(
                    tools: GovernedProgramToolExecutor(
                        registry: registry,
                        policy: .init(
                            autonomyMode: .auto_observe
                        )
                    )
                )
            )
        )
        let execution = try await runner.execute(
            ClassificationPropagationProgram(),
            input: ClassificationPropagationInput()
        )
        let output = try Expect.notNil(
            execution.output,
            "authored Program handler receives the propagated classification"
        )
        let step = try Expect.notNil(
            execution.record.steps.first,
            "classified tool failure remains present in the Program trace"
        )
        let recovery = try Expect.notNil(
            step.recovery,
            "classified tool failure retains its propagated Recovery.Record"
        )
        let calls = await probe.count()

        try Expect.equal(
            calls,
            1,
            "classified failure is not mechanically retried without a recovery policy"
        )
        try Expect.equal(
            execution.record.outcome,
            .succeeded,
            "authored Program handling may recover semantically after Runtime propagates the classified failure"
        )
        try Expect.equal(
            step.failure?.type,
            String(reflecting: ProgramToolFailure.self),
            "failed tool step preserves the public Program tool failure"
        )
        try Expect.equal(
            output.resultIsError,
            true,
            "authored Program handler receives the failed operation result"
        )
        try Expect.equal(
            output.kind,
            Recovery.Kind.authorization_required.rawValue,
            "authored Program handler receives the classified incident kind"
        )
        try Expect.equal(
            output.effect,
            Recovery.EffectState.not_applied.rawValue,
            "authored Program handler receives not-applied effect evidence"
        )
        try Expect.equal(
            output.retry,
            Recovery.RetrySafety.safe.rawValue,
            "authored Program handler receives safe retry evidence"
        )
        try Expect.equal(
            output.outcome,
            Recovery.Outcome.propagated.rawValue,
            "authored Program handler sees that Runtime propagated rather than recovered mechanically"
        )
        try Expect.equal(
            output.hasPlan,
            false,
            "propagated classification does not invent a recovery plan"
        )
        try Expect.equal(
            output.attempts,
            0,
            "propagated classification does not invent recovery attempts"
        )
        try Expect.equal(
            recovery.incident.kind,
            .authorization_required,
            "Program trace preserves the classified incident"
        )
        try Expect.equal(
            recovery.plan == nil,
            true,
            "Program trace records no mechanical recovery plan"
        )
        try Expect.equal(
            recovery.attempts.count,
            0,
            "Program trace records no mechanical recovery attempts"
        )
        try Expect.equal(
            recovery.outcome,
            .propagated,
            "Program trace records explicit propagation"
        )
        try Expect.equal(
            recovery.state.effect,
            .not_applied,
            "Program trace preserves authoritative not-applied state"
        )
        try Expect.equal(
            recovery.state.retry,
            .safe,
            "Program trace preserves authoritative retry safety"
        )

        return [
            .field(
                "calls",
                String(calls)
            ),
            .field(
                "program_outcome",
                execution.record.outcome.rawValue
            ),
            .field(
                "kind",
                recovery.incident.kind.rawValue
            ),
            .field(
                "effect",
                recovery.state.effect.rawValue
            ),
            .field(
                "retry",
                recovery.state.retry.rawValue
            ),
            .field(
                "recovery_outcome",
                recovery.outcome.rawValue
            ),
        ]
    }
}
