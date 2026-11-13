import Agentic
import Foundation
import Primitives
import Schema

/// Runtime execution for an installed Program: checkpointed execution and
/// resume through `ProgramExecutor`, opening the binding's authored type.
public extension ProgramBinding {
    var semanticInputSchema: JSONSchema {
        contract.input
    }

    var semanticOutputSchema: JSONSchema {
        contract.output
    }

    var modelFacingInputSchema: JSONSchema {
        CapabilityModelInputSchema.envelope(
            semanticInput: semanticInputSchema
        )
    }

    func execute(
        input: JSONValue,
        realization: JSONValue? = nil,
        sessionID: String? = nil,
        services: RuntimeServices = .init(),
        metadata: [String: String] = [:]
    ) async throws -> ProgramExecutionRecord {
        try await program.execute(
            defaultRealization: defaultRealization,
            input: input,
            realization: realization,
            sessionID: sessionID,
            services: services,
            metadata: metadata
        )
    }

    func resume(
        from checkpoint: ProgramCheckpoint,
        interaction response: Run.Interaction.Response,
        services: RuntimeServices = .init()
    ) async throws -> ProgramExecutionRecord {
        try await program.resume(
            from: checkpoint,
            interaction: response,
            services: services
        )
    }
}

private extension Program {
    func execute(
        defaultRealization: (any Sendable)?,
        input: JSONValue,
        realization: JSONValue?,
        sessionID: String?,
        services: RuntimeServices,
        metadata: [String: String]
    ) async throws -> ProgramExecutionRecord {
        let decodedInput = try JSONCoding.default.decode(
            Input.self,
            from: input
        )

        let appliedRealization: ProgramRealization<Self>?

        if let realization {
            appliedRealization = try JSONCoding.default.decode(
                ProgramRealization<Self>.self,
                from: realization
            )
        } else {
            appliedRealization = defaultRealization as? ProgramRealization<Self>
        }

        return try await ProgramExecutor(
            services: services
        ).execute(
            self,
            input: decodedInput,
            realization: appliedRealization,
            sessionID: sessionID,
            metadata: metadata
        ).record
    }

    func resume(
        from checkpoint: ProgramCheckpoint,
        interaction response: Run.Interaction.Response,
        services: RuntimeServices
    ) async throws -> ProgramExecutionRecord {
        try await ProgramExecutor(
            services: services
        ).resume(
            self,
            from: checkpoint,
            interaction: response
        ).record
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
