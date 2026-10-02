import Agentic
import AgenticRuntime
import AgenticStandard
import Macros
import Schema
import TestFlows
import Workspace

@JSONSchema
private struct CapabilityStateFixtureInput:
    HashableSource
{
    init() {}
}

@JSONSchema
private struct CapabilityStateFixtureOutput:
    HashableResult
{
    let value: String

    init(
        value: String
    ) {
        self.value = value
    }
}

private struct CapabilityStateAvailableTool:
    Tool
{
    typealias Input = CapabilityStateFixtureInput
    typealias Output = CapabilityStateFixtureOutput

    static let definition = ToolDefinition(
        identifier: "capability_state_available",
        purpose: "Available capability-state fixture tool.",
        risk: .observe
    )

    func call(
        _ input: Input,
        workspace _: WorkspaceContext?
    ) async throws -> Output {
        _ = input

        return .init(
            value: "available"
        )
    }
}

private struct CapabilityStateUnavailableTool:
    Tool
{
    typealias Input = CapabilityStateFixtureInput
    typealias Output = CapabilityStateFixtureOutput

    static let definition = ToolDefinition(
        identifier: "capability_state_unavailable",
        purpose: "Installed but unavailable capability-state fixture tool.",
        risk: .observe
    )

    func call(
        _ input: Input,
        workspace _: WorkspaceContext?
    ) async throws -> Output {
        _ = input

        return .init(
            value: "unavailable"
        )
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runAgentCapabilityState()
        async throws -> [TestDiagnostic]
    {
        var registry = ToolRegistry()

        try registry.register(
            CapabilityStateAvailableTool()
        )
        try registry.register(
            CapabilityStateUnavailableTool()
        )

        var installedDefinitions =
            registry.modelFacingDefinitions
        installedDefinitions.append(
            .init(
                identifier: Standard.Tools.FindTools.definition.identifier,
                description: Standard.Tools.FindTools.definition.purpose,
                risk: Standard.Tools.FindTools.definition.risk
            )
        )

        let capabilities = AgentCapabilitySet(
            tools: [
                CapabilityStateAvailableTool.definition.identifier,
                Standard.Tools.FindTools.identifier,
            ]
        )
        let state = AgentCapabilityState(
            installed: installedDefinitions,
            capabilities: capabilities,
            visibility: .discoverable(
                [
                    Standard.Tools.FindTools.identifier,
                ]
            )
        )

        try registry.register(
            Standard.Tools.FindTools(
                availability: state.available,
                exposure: state
            )
        )

        let initial = try await state.snapshot(
            in: registry
        )

        try Expect.equal(
            initial.installed.contains(
                CapabilityStateUnavailableTool.definition.identifier
            ),
            true,
            "installed universe retains tools that are unavailable to this agent"
        )
        try Expect.equal(
            initial.available.contains(
                CapabilityStateUnavailableTool.definition.identifier
            ),
            false,
            "availability intersects the configured agent capability set with installation"
        )
        try Expect.equal(
            initial.visible.contains(
                Standard.Tools.FindTools.identifier
            ),
            true,
            "find_tools may be initially visible while other available tools remain hidden"
        )
        try Expect.equal(
            initial.visible.contains(
                CapabilityStateAvailableTool.definition.identifier
            ),
            false,
            "available tools need not initially consume model context"
        )

        let findTools = Standard.Tools.FindTools(
            availability: state.available,
            exposure: state
        )
        let availableResult = try await findTools.call(
            .init(
                query: CapabilityStateAvailableTool.definition.identifier.rawValue,
                maximumResults: 1
            ),
            workspace: nil
        )

        try Expect.equal(
            availableResult.tools.map(\.identifier),
            [
                CapabilityStateAvailableTool.definition.identifier,
            ],
            "find_tools searches the available capability universe"
        )
        try Expect.equal(
            availableResult.activated,
            [
                CapabilityStateAvailableTool.definition.identifier,
            ],
            "find_tools may promote an available hidden tool into visibility"
        )

        let unavailableResult = try await findTools.call(
            .init(
                query: CapabilityStateUnavailableTool.definition.identifier.rawValue,
                maximumResults: 1
            ),
            workspace: nil
        )

        try Expect.equal(
            unavailableResult.tools
                .map(\.identifier)
                .contains(
                    CapabilityStateUnavailableTool.definition.identifier
                ),
            false,
            "find_tools never returns an installed tool that is unavailable to the agent"
        )
        try Expect.equal(
            unavailableResult.activated.contains(
                CapabilityStateUnavailableTool.definition.identifier
            ),
            false,
            "find_tools never promotes an unavailable tool into visibility"
        )

        let final = try await state.snapshot(
            in: registry
        )

        try Expect.equal(
            final.visible.contains(
                CapabilityStateAvailableTool.definition.identifier
            ),
            true,
            "discovery promotes the matching available tool into model visibility"
        )
        try Expect.equal(
            final.visible.contains(
                CapabilityStateUnavailableTool.definition.identifier
            ),
            false,
            "visibility remains a subset of availability"
        )

        return [
            .field(
                "installed",
                String(final.installed.count)
            ),
            .field(
                "available",
                String(final.available.count)
            ),
            .field(
                "visible",
                String(final.visible.count)
            ),
        ]
    }
}
