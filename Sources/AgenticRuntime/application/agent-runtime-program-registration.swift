import Agentic
import Foundation
import Primitives

public struct ProgramRegistration:
    Sendable
{
    public let registeredProgram: RegisteredProgram

    private let executeHandler:
        @Sendable (
            JSONValue,
            JSONValue?,
            AgentRuntimeServices,
            [String: String]
        ) async throws -> ProgramExecutionRecord

    private let resumeHandler:
        @Sendable (
            ProgramCheckpoint,
            AgentInteraction.Response,
            AgentRuntimeServices
        ) async throws -> ProgramExecutionRecord

    public init<ProgramType: Program>(
        _ program: ProgramType,
        defaultRealization: ProgramRealization<ProgramType>? = nil
    ) {
        self.registeredProgram = RegisteredProgram(
            program
        )

        self.executeHandler = {
            input,
            realization,
            services,
            metadata
            in
            let decodedInput = try JSONToolBridge.decode(
                ProgramType.Input.self,
                from: input
            )

            let appliedRealization: ProgramRealization<ProgramType>?

            if let realization {
                appliedRealization = try JSONToolBridge.decode(
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
        registeredProgram.identifier
    }

    public var definition: ProgramDefinition {
        registeredProgram.definition
    }

    public func execute(
        input: JSONValue,
        realization: JSONValue? = nil,
        services: AgentRuntimeServices = .init(),
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
        interaction response: AgentInteraction.Response,
        services: AgentRuntimeServices = .init()
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
    case registrationUnavailable(
        ProgramIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .registrationUnavailable(let identifier):
            return "No Runtime execution registration is installed for program '\(identifier.rawValue)'."
        }
    }
}
