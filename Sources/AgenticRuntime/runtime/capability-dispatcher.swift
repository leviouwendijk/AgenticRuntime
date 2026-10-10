import Agentic
import Primitives

/// A semantic Runtime invocation, independent of provider tool-call transport.
/// Each case retains its native execution contract and result type.
public enum CapabilityInvocation: Sendable {
    case tool(ToolCall)
    case program(
        identifier: ProgramIdentifier,
        input: JSONValue,
        realization: JSONValue?
    )
    case inference(
        identifier: InferenceIdentifier,
        input: JSONValue,
        realization: InferenceRealizationConfiguration?
    )
    case agent(
        identifier: AgentIdentifier,
        request: AgentRequest,
        sessionID: String
    )

    public enum Target: Sendable, Codable, Hashable {
        case tool(ToolIdentifier)
        case program(ProgramIdentifier)
        case inference(InferenceIdentifier)
        case agent(AgentIdentifier)

        public func isVisible(
            in capabilities: AgentCapabilitySet
        ) -> Bool {
            switch self {
            case .tool(let identifier):
                return capabilities.tools.contains(identifier)
            case .program(let identifier):
                return capabilities.programs.contains(identifier)
            case .inference(let identifier):
                return capabilities.inferences.contains(identifier)
            case .agent(let identifier):
                return capabilities.agents.contains(identifier)
            }
        }
    }

    public enum Outcome: Sendable {
        case tool(ToolCall.Response)
        case program(ProgramExecutionRecord)
        case inference(InferenceInvocation.Response)
        case agent(AgentRunner.Result)
    }

    public var target: Target {
        switch self {
        case .tool(let call):
            return .tool(call.tool)
        case .program(let identifier, _, _):
            return .program(identifier)
        case .inference(let identifier, _, _):
            return .inference(identifier)
        case .agent(let identifier, _, _):
            return .agent(identifier)
        }
    }
}

/// Only the trusted Runtime caller constructs an invocation origin; model
/// arguments never select their own authorization origin.
public enum CapabilityInvocationOrigin: Sendable {
    case host
    case program
    case model(projection: ModelCapabilityProjection, function: String)
    case delegated_agent
}

public enum CapabilityInvocationError: Error, Sendable {
    case notInstalled(CapabilityInvocation.Target)
    case notAvailable(CapabilityInvocation.Target)
    case notAdvertised(CapabilityInvocation.Target)
    case missingInferenceExecutor(InferenceIdentifier)
    case agentRequiresDelegation(AgentIdentifier)
}

/// Dispatches explicitly authorized semantic capabilities into their existing
/// execution boundaries. This is NOT a provider-schema projection and does not
/// grant authority merely because a registration exists in the Runtime.
public struct CapabilityDispatcher: Sendable {
    public let runtime: AgenticRuntime
    public let capabilityState: AgentCapabilityState
    public let inventory: CapabilityInventory?
    public let services: RuntimeServices
    public let configuration: AgentRunner.Configuration

    public init(
        runtime: AgenticRuntime,
        capabilityState: AgentCapabilityState,
        inventory: CapabilityInventory? = nil,
        services: RuntimeServices = .init(),
        configuration: AgentRunner.Configuration = .default
    ) {
        self.runtime = runtime
        self.capabilityState = capabilityState
        self.inventory = inventory
        self.services = services
        self.configuration = configuration
    }

    public func invoke(
        _ invocation: CapabilityInvocation,
        origin: CapabilityInvocationOrigin
    ) async throws -> CapabilityInvocation.Outcome {
        let target = invocation.target
        let snapshot = await capabilityState.snapshot()
        let installed: AgentCapabilitySet
        if let inventory {
            installed = await inventory.snapshot().installed
        } else {
            installed = snapshot.installed
        }
        guard target.isVisible(in: installed) else {
            throw CapabilityInvocationError.notInstalled(target)
        }
        switch origin {
        case .host:
            // A trusted Host can use installed bindings without altering an
            // Agent's available or directly projected capability selection.
            break
        case .program:
            guard target.isVisible(in: snapshot.available) else {
                throw CapabilityInvocationError.notAvailable(target)
            }
        case .model(let projection, let function):
            guard projection.target(named: function) == target else {
                throw CapabilityInvocationError.notAdvertised(target)
            }
            guard target.isVisible(in: snapshot.available) else {
                throw CapabilityInvocationError.notAvailable(target)
            }
        case .delegated_agent:
            // Parent/child authority requires the later delegation control plane.
            if case .agent(let identifier, _, _) = invocation {
                throw CapabilityInvocationError.agentRequiresDelegation(identifier)
            }
            throw CapabilityInvocationError.notAvailable(target)
        }

        switch invocation {
        case .tool(let call):
            // Preserve Tool preflight, ActionRisk, approval, and recovery;
            // never invoke the underlying registration directly.
            let tools: ToolRegistry
            if let inventory {
                tools = await inventory.tools()
            } else {
                tools = runtime.tools
            }
            let effectiveCatalog: Catalog
            if let inventory {
                effectiveCatalog = await inventory.catalog()
            } else {
                effectiveCatalog = services.tooling.catalog
            }
            let inspections: [CapabilityInspection]
            if let inventory {
                inspections = await inventory.capabilityInspections()
            } else {
                inspections = runtime.installed.capabilityInspections()
            }
            let governed = GovernedAgentToolCallResolver(
                registry: tools,
                visibleToolIdentifiers: [call.tool],
                policy: configuration.toolExecutionPolicy,
                recovery: configuration.recovery,
                context: ToolContext(
                    workspace: services.tooling.workspace,
                    catalog: effectiveCatalog,
                    capabilities: capabilityState,
                    inspections: inspections
                ),
                approvalHandler: services.tooling.approvalHandler
            )
            let result = try await governed.resolve(call)
            return .tool(result)

        case .program(let identifier, let input, let realization):
            if let inventory {
                guard let program = await inventory.program(identifier) else {
                    throw ProgramExecutionError.bindingUnavailable(identifier)
                }
                return .program(try await program.execute(
                    input: input,
                    realization: realization,
                    services: services,
                    metadata: services.metadata
                ))
            }
            return .program(
                try await runtime.executeProgram(
                    identifiedBy: identifier,
                    input: input,
                    realization: realization,
                    services: services,
                    metadata: services.metadata
                )
            )

        case .inference(let identifier, let input, let realization):
            guard let executor = services.program.inference else {
                throw CapabilityInvocationError.missingInferenceExecutor(
                    identifier
                )
            }
            if let inventory {
                guard let inference = await inventory.inference(identifier) else {
                    throw InferenceRegistryError.unknownInference(identifier)
                }
                return .inference(try await inference.execute(
                    input: input,
                    realization: realization,
                    using: executor
                ))
            }
            return .inference(
                try await runtime.executeInference(
                    identifiedBy: identifier,
                    input: input,
                    realization: realization,
                    using: executor
                )
            )

        case .agent(let identifier, _, _):
            // A visible Agent is not necessarily delegable. Do not start a
            // detached root run masquerading as a child: the delegation pass
            // must provide parent identity, budgets, reentry and run lineage.
            throw CapabilityInvocationError.agentRequiresDelegation(
                identifier
            )
        }
    }
}
