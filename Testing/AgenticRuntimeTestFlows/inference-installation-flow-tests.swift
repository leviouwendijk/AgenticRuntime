import Agentic
import AgenticRuntime
import Foundation
import Macros
import Primitives
import Schema
import TestFlows

@JSONSchema
private struct InstalledInferenceInput: Sendable, Codable, Hashable {
    let value: String
}

private enum InstalledInferenceFixture: Inference {
    typealias Input = InstalledInferenceInput
    typealias Output = JSONValue

    static let definition = InferenceDefinition(
        identifier: "fixture.inference_installation.installed",
        purpose: "Exercises executable Runtime Inference installation."
    )
}

private enum InferenceInstallationAgentFixture: Agent {
    typealias Input = InstalledInferenceInput
    typealias Output = JSONValue

    static let purpose = "Tests installed and semantic-only Inference authority."
    static let unavailable = InferenceIdentifier(
        rawValue: "fixture.inference_installation.semantic_only"
    )
    static let capabilities = AgentCapabilities(
        available: .init(
            inferences: .init(
                members: [
                    InstalledInferenceFixture.definition.identifier,
                    unavailable,
                ]
            )
        ),
        visible: .init(
            inferences: .init(
                members: [
                    InstalledInferenceFixture.definition.identifier,
                    unavailable,
                ]
            )
        )
    )
    static let definition = AgentDefinition(
        identifier: "fixture.inference_installation.agent",
        purpose: purpose,
        capabilities: capabilities
    )
}

private struct InstalledInferenceExecutor: InferenceExecuting {
    func execute(
        _ invocation: InferenceInvocation
    ) async throws -> InferenceInvocation.Response {
        let input = try JSONDecoder().decode(
            InstalledInferenceInput.self,
            from: invocation.input
        )
        return InferenceInvocation.Response(
            output: try JSONEncoder().encode(
                JSONValue.string("inferred:\(input.value)")
            ),
            record: InferenceExecutionRecord(
                inference: invocation.definition.identifier,
                strategy: invocation.realization.strategy,
                budget: invocation.realization.budget
            )
        )
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runInferenceInstallation()
        async throws -> [TestDiagnostic]
    {
        let realization = InferenceRealizationConfiguration(
            strategy: "fixture.direct",
            instructions: "Return the fixture inference output.",
            budget: .singleAttempt
        )
        let application = Agentic.application(
            "fixture.inference_installation"
        ) {
            install(
                InstalledInferenceFixture.self,
                realization: realization
            )
            install(InferenceInstallationAgentFixture.self)
        }
        let runtime = try await AgenticRuntime(application: application)
        let identifier = InstalledInferenceFixture.definition.identifier
        let agent = try runtime.realizeAgent(
            identifiedBy: InferenceInstallationAgentFixture.definition.identifier
        )

        try Expect.equal(
            runtime.inferences.definitions.map(\.identifier),
            [identifier],
            "Only executable registrations populate the Inference registry."
        )
        try Expect.equal(
            agent.installed.inferences,
            [identifier],
            "Installed Inferences come from executable Runtime registrations."
        )
        try Expect.equal(
            agent.available.inferences,
            [identifier],
            "A semantic-only Inference is excluded from Agent authority."
        )
        try Expect.equal(
            agent.visible.inferences,
            [identifier],
            "Authored visibility retains a registered Inference within availability."
        )
        try Expect.equal(
            runtime.inferences.binding(
                identifiedBy: InferenceInstallationAgentFixture.unavailable
            ) == nil,
            true,
            "A noninstalled Inference is never executable."
        )

        let execution = try await runtime.executeInference(
            identifiedBy: identifier,
            input: try JSONCoding.default.value(
                InstalledInferenceInput(value: "hello")
            ),
            using: InstalledInferenceExecutor()
        )
        let output = try JSONDecoder().decode(
            JSONValue.self,
            from: execution.output
        )
        try Expect.equal(
            output,
            JSONValue.string("inferred:hello"),
            "Registered Inference executes through the canonical typed invocation."
        )
        try Expect.equal(
            execution.record.inference,
            identifier,
            "Execution evidence retains the installed Inference identity."
        )

        return [
            .field("installed_inferences", String(agent.installed.inferences.count)),
            .field("visible_inferences", String(agent.visible.inferences.count)),
            .field("semantic_only_excluded", "true"),
            .field("output", "inferred:hello"),
        ]
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runCapabilityDispatch()
        async throws -> [TestDiagnostic]
    {
        let realization = InferenceRealizationConfiguration(
            strategy: "fixture.direct",
            instructions: "Return the fixture inference output.",
            budget: .singleAttempt
        )
        let application = Agentic.application(
            "fixture.capability_dispatch"
        ) {
            install(
                InstalledInferenceFixture.self,
                realization: realization
            )
            install(InferenceInstallationAgentFixture.self)
        }
        let runtime = try await AgenticRuntime(application: application)
        let agent = try runtime.realizeAgent(
            identifiedBy: InferenceInstallationAgentFixture.definition.identifier
        )
        let state = agent.makeCapabilityState()
        let dispatcher = CapabilityDispatcher(
            runtime: runtime,
            capabilityState: state,
            services: RuntimeServices(
                program: .init(inference: InstalledInferenceExecutor())
            )
        )
        let identifier = InstalledInferenceFixture.definition.identifier
        let input = try JSONCoding.default.value(
            InstalledInferenceInput(value: "dispatched")
        )
        let invocation = CapabilityInvocation.inference(
            identifier: identifier,
            input: input,
            realization: nil
        )

        let authorizationProjection = try await runtime.modelProjection(for: state)
        let authorizedFunction = try Expect.notNil(
            authorizationProjection.name(for: .inference(identifier)),
            "Installed inference must have a request-bound provider function name."
        )

        let outcome = try await dispatcher.invoke(
            invocation,
            origin: .program
        )
        var executed = false
        if case .inference(let execution) = outcome {
            let output = try JSONDecoder().decode(
                JSONValue.self,
                from: execution.output
            )
            executed = output == JSONValue.string("inferred:dispatched")
        }
        try Expect.equal(
            executed,
            true,
            "Authorized Inference dispatch uses the installed executor."
        )

        await state.hide(.init(inferences: [identifier]))
        let hiddenProgramOutcome = try await dispatcher.invoke(
            invocation,
            origin: .program
        )
        let hiddenProgramExecuted: Bool
        if case .inference = hiddenProgramOutcome {
            hiddenProgramExecuted = true
        } else {
            hiddenProgramExecuted = false
        }
        try Expect.equal(hiddenProgramExecuted, true,
            "An authorized Program does not depend on model visibility.")

        var guessedModelRejected = false
        do {
            _ = try await dispatcher.invoke(
                invocation,
                origin: .model(projection: authorizationProjection, function: "guessed")
            )
        } catch CapabilityInvocationError.notAdvertised {
            guessedModelRejected = true
        }
        try Expect.equal(guessedModelRejected, true,
            "A model cannot invoke a function absent from its request mapping.")

        let mappedModelOutcome = try await dispatcher.invoke(
            invocation,
            origin: .model(projection: authorizationProjection, function: authorizedFunction)
        )
        let mappedModelExecuted: Bool
        if case .inference = mappedModelOutcome {
            mappedModelExecuted = true
        } else {
            mappedModelExecuted = false
        }
        try Expect.equal(mappedModelExecuted, true,
            "An already-advertised request remains valid after merely hiding the schema.")

        await state.disable(.init(inferences: [identifier]))
        var revokedProgramRejected = false
        do {
            _ = try await dispatcher.invoke(invocation, origin: .program)
        } catch CapabilityInvocationError.notAvailable {
            revokedProgramRejected = true
        }
        try Expect.equal(revokedProgramRejected, true,
            "Revoking availability blocks a Program even when its binding remains installed.")

        let hostOutcome = try await dispatcher.invoke(invocation, origin: .host)
        let hostExecuted: Bool
        if case .inference = hostOutcome {
            hostExecuted = true
        } else {
            hostExecuted = false
        }
        try Expect.equal(hostExecuted, true,
            "A trusted Host can invoke an installed binding outside Agent projection.")

        var uninstalledToolRejected = false
        do {
            _ = try await dispatcher.invoke(
                .tool(
                    ToolCall(
                        id: "not-installed",
                        tool: "fixture.uninstalled",
                        input: .null
                    )
                ),
                origin: .host
            )
        } catch CapabilityInvocationError.notInstalled {
            uninstalledToolRejected = true
        }
        try Expect.equal(
            uninstalledToolRejected,
            true,
            "Unknown Tools are rejected before any Tool execution path."
        )

        return [
            .field("inference_dispatched", String(executed)),
            .field("hidden_program_executed", String(hiddenProgramExecuted)),
            .field("guessed_model_rejected", String(guessedModelRejected)),
            .field("revoked_program_rejected", String(revokedProgramRejected)),
            .field("trusted_host_executed", String(hostExecuted)),
            .field("unknown_tool_rejected", String(uninstalledToolRejected)),
        ]
    }
}
