import Agentic
import AgenticContext
import AgenticRuntime
import Macros
import Schema
import TestFlows

@JSONSchema
private struct ContextAllocatorRoleFixtureValue: Sendable, Codable, Hashable {
    let value: String
}

private enum ContextAllocatorRoleFixtureAgent: Agent {
    typealias Input = ContextAllocatorRoleFixtureValue
    typealias Output = ContextAllocatorRoleFixtureValue

    static let purpose = "Context allocator role routing fixture"
    static let definition = AgentDefinition(
        identifier: .init(rawValue: "fixture.context_allocator.agent"),
        purpose: purpose,
        modelSelection: .init(
            purpose: .coder,
            requirements: .init(capabilities: [.text, .reasoning]),
            constraints: .init(allowsExternal: false)
        )
    )
}

private struct ContextAllocatorRoleFixtureProgram: Program {
    typealias Input = ContextAllocatorRoleFixtureValue
    typealias Output = ContextAllocatorRoleFixtureValue

    static let definition = ProgramDefinition(
        identifier: "fixture.context_allocator.program",
        purpose: "Deterministic source investigation fixture"
    )

    func run(_ input: Input, in _: ProgramContext) async throws -> Output { input }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runContextAllocatorRoles() async throws -> [TestDiagnostic] {
        let installed = InstalledCapabilities(
            programs: [ProgramExecutionBinding(ContextAllocatorRoleFixtureProgram())],
            agents: [AgentBinding(ContextAllocatorRoleFixtureAgent.self)]
        )
        let agentID = ContextAllocatorRoleFixtureAgent.definition.identifier
        let programID = ContextAllocatorRoleFixtureProgram.definition.identifier
        let primary = try Context.Allocator.Agent(
            resolving: agentID,
            in: installed,
            modelPreferences: .init(
                preferredProfileIdentifier: "fixture.context.profile.a"
            )
        )
        let worker = try Context.Allocator.Program(
            resolving: programID, in: installed
        )
        try Expect.equal(primary.identifier, agentID,
            "Agent role resolves against installed executable bindings")
        try Expect.equal(worker.identifier, programID,
            "Program role resolves against installed executable bindings")

        let allocator = try Context.Allocator()
        try await allocator.createWorkingSet(id: "fixture.work")
        await allocator.configure(.init(
            id: "fixture.preset",
            orchestrator: primary,
            investigator: .program(worker)
        ))
        let first = try await allocator.preset("fixture.preset")
        try Expect.equal(first.revision, 1, "Initial preset revision")
        try Expect.equal(first.orchestrator?.identifier, agentID,
            "Only an Agent can occupy orchestrator position")
        guard case .program(let resolvedProgram)? = first.investigator else {
            throw ContextAllocatorRoleFixtureError.incorrectRole
        }
        try Expect.equal(resolvedProgram.identifier, programID,
            "Investigator can contain an actual installed Program")

        var unavailableAgentRejected = false
        do {
            _ = try Context.Allocator.Agent(
                resolving: .init(rawValue: "not.installed"), in: installed
            )
        } catch ContextAllocatorError.unavailableAgent {
            unavailableAgentRejected = true
        }
        try Expect.equal(unavailableAgentRejected, true,
            "Invalid Agent identity never constructs a role")

        var unavailableProgramRejected = false
        do {
            _ = try Context.Allocator.Program(
                resolving: .init(rawValue: "not.installed"), in: installed
            )
        } catch ContextAllocatorError.unavailableProgram {
            unavailableProgramRejected = true
        }
        try Expect.equal(unavailableProgramRejected, true,
            "Invalid Program identity never constructs a role")

        let changed = primary.selecting(.init(
            preferredProfileIdentifier: "fixture.context.profile.b"
        ))
        await allocator.configure(.init(
            id: "fixture.preset",
            orchestrator: changed,
            investigator: first.investigator
        ))
        let second = try await allocator.preset("fixture.preset")
        try Expect.equal(second.revision, 2, "Replacement advances preset revision")
        try Expect.equal(first.orchestrator?.modelPreferences.preferredProfileIdentifier?.rawValue,
            "fixture.context.profile.a", "Old snapshot cannot change")
        try Expect.equal(second.orchestrator?.modelPreferences.preferredProfileIdentifier?.rawValue,
            "fixture.context.profile.b", "New snapshot contains revised preference")

        let runtime = try await AgenticRuntime(application: .init(
            identifier: "fixture.context_allocator.runtime",
            components: [.agents([AgentBinding(ContextAllocatorRoleFixtureAgent.self)])]
        ))
        let invoker = ContextAllocatorRoleFixtureInvoker()
        guard let previous = first.orchestrator,
              let updated = second.orchestrator else {
            throw ContextAllocatorRoleFixtureError.incorrectRole
        }
        let previousRunner = try runtime.makeAgentRunner(
            identifiedBy: previous.identifier,
            model: .init(invoker: invoker),
            modelPreferences: previous.modelPreferences
        )
        let updatedRunner = try runtime.makeAgentRunner(
            identifiedBy: updated.identifier,
            model: .init(invoker: invoker),
            modelPreferences: updated.modelPreferences
        )
        let previousModel = await previousRunner.model
        let updatedModel = await updatedRunner.model
        try Expect.equal(previousModel.selection.preferences.preferredProfileIdentifier?.rawValue,
            "fixture.context.profile.a", "Older runner preserves its own selection")
        try Expect.equal(updatedModel.selection.preferences.preferredProfileIdentifier?.rawValue,
            "fixture.context.profile.b", "Updated runner receives revised preference")
        try Expect.equal(updatedModel.selection.purpose, .coder,
            "Authored routing purpose is unchanged")
        try Expect.equal(updatedModel.selection.requirements.capabilities.contains(.reasoning), true,
            "Authored capability requirements remain binding")
        try Expect.equal(updatedModel.selection.constraints.allowsExternal, false,
            "Authored provider privacy constraints remain binding")

        await allocator.configure(.init(
            id: "fixture.preset", orchestrator: changed
        ))
        let third = try await allocator.preset("fixture.preset")
        try Expect.equal(third.revision, 3, "Removing optional role advances revision")
        try Expect.equal(third.investigator == nil, true,
            "No placeholder investigator is needed")
        let workingSet = try await allocator.snapshot("fixture.work")
        try Expect.equal(workingSet.id, "fixture.work",
            "Preset configuration does not disturb working-set state")
        return [
            .message("Allocator retains independently revisioned optional collaborators alongside deterministic working sets"),
            .field("roles", "2"),
            .field("revision", String(third.revision))
        ]
    }
}

private struct ContextAllocatorRoleFixtureInvoker: AgentModelInvoking {
    func buffered(_ invocation: AgentModelInvocation) async throws -> AgentModelInvocation.Result {
        throw ContextAllocatorRoleFixtureError.unexpectedInvocation
    }

    func stream(_ invocation: AgentModelInvocation) -> AsyncThrowingStream<AgentModelInvocation.Event, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ContextAllocatorRoleFixtureError.unexpectedInvocation)
        }
    }
}

private enum ContextAllocatorRoleFixtureError: Error {
    case incorrectRole
    case unexpectedInvocation
}
