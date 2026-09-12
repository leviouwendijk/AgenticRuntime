import Agentic
import AgenticPrograms
import AgenticRuntime
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runApplicationProgramInstallation()
        async throws
        -> [TestFlowDiagnostic]
    {
        let defaultRealization =
            AgentProgramRealization<ApplicationProgramFixture>(
                id: "fixture.default_realization",
                inferences: [],
                metadata: [
                    "source": "application",
                ]
            )

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
            application.programRegistrations.count,
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
            runtime.programs.descriptors.map {
                $0.identifier
            },
            [
                ApplicationProgramFixture.descriptor.identifier,
            ],
            "runtime exposes installed semantic program descriptors"
        )

        let input = try JSONToolBridge.encode(
            ApplicationProgramFixture.Input(
                value: "runtime"
            )
        )
        let defaultExecution = try await runtime.executeProgram(
            identifiedBy: ApplicationProgramFixture
                .descriptor.identifier,
            input: input,
            metadata: [
                "invocation": "default",
            ]
        )

        try Expect.equal(
            defaultExecution.outcome,
            AgentProgramExecutionOutcome.succeeded,
            "runtime erased program invocation delegates to AgentProgramRunner"
        )
        try Expect.equal(
            defaultExecution.realizationIdentifier,
            defaultRealization.id,
            "runtime program registration applies its typed default realization"
        )
        try Expect.equal(
            defaultExecution.metadata[
                "invocation"
            ],
            "default",
            "runtime program execution preserves invocation metadata"
        )

        let defaultOutput = try JSONToolBridge.decode(
            ApplicationProgramFixture.Output.self,
            from: defaultExecution.output
                ?? .null
        )

        try Expect.equal(
            defaultOutput.value,
            "echo:runtime",
            "runtime execution record preserves erased program output"
        )

        let explicitRealization =
            AgentProgramRealization<ApplicationProgramFixture>(
                id: "fixture.explicit_realization",
                inferences: [],
                metadata: [
                    "source": "invocation",
                ]
            )
        let explicitExecution = try await runtime.executeProgram(
            identifiedBy: ApplicationProgramFixture
                .descriptor.identifier,
            input: input,
            realization: try JSONToolBridge.encode(
                explicitRealization
            )
        )

        try Expect.equal(
            explicitExecution.realizationIdentifier,
            explicitRealization.id,
            "explicit erased realization overrides the registration default at the Runtime boundary"
        )

        var unknownRejected = false

        do {
            _ = try await runtime.executeProgram(
                identifiedBy: "fixture.unknown_program",
                input: input
            )
        } catch AgentRuntimeProgramExecutionError
            .registrationUnavailable {
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
                runtime.programs.descriptors[0]
                    .identifier.rawValue
            ),
            .field(
                "default_realization",
                defaultExecution
                    .realizationIdentifier?
                    .rawValue
                    ?? "none"
            ),
            .field(
                "explicit_realization",
                explicitExecution
                    .realizationIdentifier?
                    .rawValue
                    ?? "none"
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
    AgentProgram
{
    struct Input:
        Sendable,
        Codable,
        Hashable
    {
        let value: String
    }

    struct Output:
        Sendable,
        Codable,
        Hashable
    {
        let value: String
    }

    static let descriptor = AgentProgramDescriptor(
        identifier: "fixture.application_program",
        title: "Application Program",
        summary: "Proves AgenticApplication installs Programs into Runtime."
    )

    func run(
        _ input: Input,
        in _: AgentProgramContext
    ) async throws -> Output {
        .init(
            value: "echo:\(input.value)"
        )
    }
}
