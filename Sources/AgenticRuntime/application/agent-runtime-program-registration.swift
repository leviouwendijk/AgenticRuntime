import Agentic
import AgenticPrograms
import Foundation
import Primitives

public struct AgentRuntimeProgramRegistration:
    Sendable
{
    public let registeredProgram: RegisteredAgentProgram

    private let executeHandler:
        @Sendable (
            JSONValue,
            JSONValue?,
            AgentRuntimeServices,
            [String: String]
        ) async throws -> AgentProgramExecutionRecord

    public init<Program: AgentProgram>(
        _ program: Program,
        defaultRealization: AgentProgramRealization<Program>? = nil
    ) {
        self.registeredProgram = RegisteredAgentProgram(
            program
        )

        self.executeHandler = {
            input,
            realization,
            services,
            metadata
            in
            let decodedInput = try JSONToolBridge.decode(
                Program.Input.self,
                from: input
            )

            let appliedRealization: AgentProgramRealization<Program>?

            if let realization {
                appliedRealization = try JSONToolBridge.decode(
                    AgentProgramRealization<Program>.self,
                    from: realization
                )
            } else {
                appliedRealization = defaultRealization
            }

            let execution = try await AgentProgramRunner(
                services: services
            ).execute(
                program,
                input: decodedInput,
                realization: appliedRealization,
                metadata: metadata
            )

            return execution.record
        }
    }

    public var identifier: AgentProgramIdentifier {
        registeredProgram.identifier
    }

    public var descriptor: AgentProgramDescriptor {
        registeredProgram.descriptor
    }

    public func execute(
        input: JSONValue,
        realization: JSONValue? = nil,
        services: AgentRuntimeServices = .init(),
        metadata: [String: String] = [:]
    ) async throws -> AgentProgramExecutionRecord {
        try await executeHandler(
            input,
            realization,
            services,
            metadata
        )
    }
}

public enum AgentRuntimeProgramExecutionError:
    Error,
    Sendable,
    LocalizedError
{
    case registrationUnavailable(
        AgentProgramIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .registrationUnavailable(let identifier):
            return "No Runtime execution registration is installed for program '\(identifier.rawValue)'."
        }
    }
}
