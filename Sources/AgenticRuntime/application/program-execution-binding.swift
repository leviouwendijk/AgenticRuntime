import Agentic
import Foundation
import Primitives
import Schema

public struct ProgramExecutionBinding:
    CapabilityBinding
{
    public let program: ProgramBinding

    public var reference: CapabilityReference {
        program.reference
    }

    /// The Core Program binding remains the source of this typed contract.
    public var capabilityContract: CapabilityContract {
        program.capabilityContract
    }

    public var semanticInputSchema: JSONSchema {
        capabilityContract.input
    }

    public var semanticOutputSchema: JSONSchema {
        capabilityContract.output
    }

    public var modelFacingInputSchema: JSONSchema {
        CapabilityModelInputSchema.envelope(
            semanticInput: semanticInputSchema
        )
    }

    private let executeHandler:
        @Sendable (
            JSONValue,
            JSONValue?,
            RuntimeServices,
            [String: String]
        ) async throws -> ProgramExecutionRecord

    private let resumeHandler:
        @Sendable (
            ProgramCheckpoint,
            Run.Interaction.Response,
            RuntimeServices
        ) async throws -> ProgramExecutionRecord

    public init<ProgramType: Program>(
        _ program: ProgramType,
        defaultRealization: ProgramRealization<ProgramType>? = nil
    ) {
        self.program = ProgramBinding(
            program
        )

        self.executeHandler = {
            input,
            realization,
            services,
            metadata
            in
            let decodedInput = try JSONCoding.default.decode(
                ProgramType.Input.self,
                from: input
            )

            let appliedRealization: ProgramRealization<ProgramType>?

            if let realization {
                appliedRealization = try JSONCoding.default.decode(
                    ProgramRealization<ProgramType>.self,
                    from: realization
                )
            } else {
                appliedRealization = defaultRealization
            }

            let execution = try await ProgramRunner(
                services: services
            ).execute(
                program,
                input: decodedInput,
                realization: appliedRealization,
                metadata: metadata
            )

            return execution.record
        }

        self.resumeHandler = {
            checkpoint,
            response,
            services
            in
            let execution = try await ProgramRunner(
                services: services
            ).resume(
                program,
                from: checkpoint,
                interaction: response
            )

            return execution.record
        }
    }

    public var identifier: ProgramIdentifier {
        program.identifier
    }

    public var definition: ProgramDefinition {
        program.definition
    }

    public func execute(
        input: JSONValue,
        realization: JSONValue? = nil,
        services: RuntimeServices = .init(),
        metadata: [String: String] = [:]
    ) async throws -> ProgramExecutionRecord {
        try await executeHandler(
            input,
            realization,
            services,
            metadata
        )
    }

    public func resume(
        from checkpoint: ProgramCheckpoint,
        interaction response: Run.Interaction.Response,
        services: RuntimeServices = .init()
    ) async throws -> ProgramExecutionRecord {
        try await resumeHandler(
            checkpoint,
            response,
            services
        )
    }
}

public enum ProgramExecutionError:
    Error,
    Sendable,
    LocalizedError
{
    case bindingUnavailable(
        ProgramIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .bindingUnavailable(let identifier):
            return "No Runtime execution binding is installed for program '\(identifier.rawValue)'."
        }
    }
}
