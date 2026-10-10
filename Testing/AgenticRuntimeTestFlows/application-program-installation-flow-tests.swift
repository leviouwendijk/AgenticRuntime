import Agentic
import AgenticRuntime
import Primitives
import Schema
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runApplicationProgramInstallation()
        async throws
        -> [TestDiagnostic]
    {
        let defaultRealization =
            try ProgramRealization<ApplicationProgramFixture>()

        let application = Agentic.application(
            "fixture.program_application"
        ) {
            programs {
                program(
                    ApplicationProgramFixture(),
                    realization: defaultRealization
                )
            }
        }

        try Expect.equal(
            application.programBindings.count,
            1,
            "application DSL captures installed program registrations"
        )

        let runtime = try await AgenticRuntime(
            application: application
        )

        try Expect.equal(
            runtime.programs.count,
            1,
            "runtime realizes application programs into one ProgramRegistry"
        )
        try Expect.equal(
            runtime.programs.definitions.map {
                $0.identifier
            },
            [
                ApplicationProgramFixture.definition.identifier,
            ],
            "runtime exposes installed semantic program descriptors"
        )

        let input = try JSONValue.encoding(
            ApplicationProgramFixture.Input(
                value: "runtime"
            )
        )
        let defaultExecution = try await runtime.executeProgram(
            identifiedBy: ApplicationProgramFixture
                .definition.identifier,
            input: input,
            metadata: [
                "invocation": "default",
            ]
        )

        try Expect.equal(
            defaultExecution.outcome,
            ProgramExecutionOutcome.succeeded,
            "runtime erased program invocation delegates to ProgramRunner"
        )
        try Expect.equal(
            defaultRealization.bindings.count,
            0,
            "application accepts an empty typed default Program realization"
        )
        try Expect.equal(
            defaultExecution.metadata[
                "invocation"
            ],
            "default",
            "runtime program execution preserves invocation metadata"
        )

        let defaultOutput = try (
            defaultExecution.output ?? .null
        ).decode(
            ApplicationProgramFixture.Output.self
        )

        try Expect.equal(
            defaultOutput.value,
            "echo:runtime",
            "runtime execution record preserves erased program output"
        )

        let explicitRealization =
            try ProgramRealization<ApplicationProgramFixture>()
        let explicitExecution = try await runtime.executeProgram(
            identifiedBy: ApplicationProgramFixture
                .definition.identifier,
            input: input,
            realization: try JSONValue.encoding(
                explicitRealization
            )
        )

        try Expect.equal(
            explicitExecution.outcome,
            .succeeded,
            "runtime accepts an explicit erased Program realization override"
        )

        var unknownRejected = false

        do {
            _ = try await runtime.executeProgram(
                identifiedBy: "fixture.unknown_program",
                input: input
            )
        } catch ProgramExecutionError
            .bindingUnavailable {
            unknownRejected = true
        }

        try Expect.equal(
            unknownRejected,
            true,
            "runtime direct program execution rejects identifiers that were not installed by the application"
        )

        return [
            .field(
                "programs",
                String(runtime.programs.count)
            ),
            .field(
                "program",
                runtime.programs.definitions[0]
                    .identifier.rawValue
            ),
            .field(
                "default_outcome",
                defaultExecution.outcome.rawValue
            ),
            .field(
                "explicit_outcome",
                explicitExecution.outcome.rawValue
            ),
            .field(
                "output",
                defaultOutput.value
            ),
            .field(
                "unknown_rejected",
                String(unknownRejected)
            ),
        ]
    }
}

private struct ApplicationProgramFixture:
    Program
{
    struct Input:
        Sendable,
        Codable,
        Hashable,
        JSONSchemaProviding
    {
        let value: String

        static var jsonschema: JSONSchema {
            .object(
                properties: [
                    .init(
                        name: "value",
                        schema: .string(),
                        required: true
                    ),
                ],
                additionalProperties: .disallowed
            )
        }
    }

    struct Output:
        Sendable,
        Codable,
        Hashable,
        JSONSchemaProviding
    {
        let value: String

        static var jsonschema: JSONSchema {
            .object(
                properties: [
                    .init(
                        name: "value",
                        schema: .string(),
                        required: true
                    ),
                ],
                additionalProperties: .disallowed
            )
        }
    }

    static let definition = ProgramDefinition(
        identifier: "fixture.application_program",
        purpose: "Proves AgenticApplication installs Programs into Runtime.",
        title: "Application Program"
    )

    func run(
        _ input: Input,
        in _: ProgramContext
    ) async throws -> Output {
        .init(
            value: "echo:\(input.value)"
        )
    }
}
