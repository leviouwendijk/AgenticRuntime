import Agentic
import AgenticExecution
import AgenticIO
import AgenticInterfaces
import AgenticRuntime
import AgenticWorkspace
import Foundation

enum AppleWriteApprovalTestCase {
    static func make() -> AgenticInterfaceTestCase {
        .init(
            id: "apple-write",
            summary: "Generate an Apple fragment, stage write_file, and use the terminal approval picker."
        ) { arguments in
            try await run(
                arguments
            )
        }
    }

    static func run(
        _ arguments: [String]
    ) async throws {
        let configuration = try AppleWriteApprovalConfiguration.parse(
            arguments
        )
        let workspaceRoot = try AgenticInterfaceTestEnvironment.workspaceRoot()
        let workspace = try AgentWorkspace(
            root: workspaceRoot
        )
        let generatedMiddle = try await AppleStructuredQuoteGenerator().generateMiddleFragment()
        let content = FileContentComposer.compose(
            workspaceRoot: workspaceRoot,
            generatedMiddle: generatedMiddle
        )
        let prompt = "write \(configuration.targetPath) with an Apple-generated philosophical middle fragment"

        var registry = ToolRegistry()
        try registry.register(
            WriteFileTool()
        )

        let historyStore = FileHistoryStore(
            sessionsdir: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "agentic-interface-test-\(UUID().uuidString)",
                    isDirectory: true
                )
        )

        // let presenter = TerminalAgenticRunPresenter()
        let presenter = AgenticInterfaceRuntimeFactory.presenter()

        let picker = TestFlowApprovalPicker(
            interaction: AgenticInterfaceTestEnvironment.interaction,
            presenter: presenter
        )

        let runner = AgentRunner(
            adapter: ScriptedWriteModelAdapter(
                path: configuration.targetPath,
                content: content
            ),
            configuration: .init(
                maximumIterations: 4,
                autonomyMode: .auto_observe,
                historyPersistenceMode: .checkpointmutation
            ),
            toolRegistry: registry,
            workspace: workspace,
            historyStore: historyStore
        )

        try await presenter.present(
            .runStarted(
                prompt: prompt
            )
        )

        let initialResult = try await runner.run(
            AgentRequest(
                messages: [
                    .init(
                        role: .user,
                        text: prompt
                    )
                ]
            )
        )

        guard let pendingApproval = initialResult.pendingApproval else {
            try await presenter.present(
                initialResult
            )

            try await presenter.present(
                .runCompleted(
                    summary: "Run did not suspend for approval."
                )
            )
            return
        }

        try await presenter.present(
            .toolCallProposed(
                pendingApproval.toolCall
            )
        )

        try await presenter.present(
            .toolPreflight(
                pendingApproval.preflight
            )
        )

        try await presenter.present(
            initialResult
        )

        let choice = try await picker.pick(
            AgenticApprovalPrompt(
                pendingApproval: pendingApproval,
                title: "Runtime suspended for approval"
            )
        )

        switch choice {
        case .approve:
            try await presenter.present(
                .approvalDecision(
                    .approved
                )
            )

            let resumed = try await runner.resume(
                sessionID: initialResult.sessionID,
                approvalDecision: .approved,
                metadata: [
                    "summary": "approved from aginttest terminal interface"
                ]
            )

            try await presenter.present(
                resumed
            )

        case .deny:
            try await presenter.present(
                .approvalDecision(
                    .denied
                )
            )

            let resumed = try await runner.resume(
                sessionID: initialResult.sessionID,
                approvalDecision: .denied,
                metadata: [
                    "summary": "denied from aginttest terminal interface"
                ]
            )

            try await presenter.present(
                resumed
            )

        case .stopRun:
            try await presenter.present(
                .runStopped(
                    reason: "User stopped the run from the approval picker."
                )
            )

        case .inspectDetails,
             .showDiff:
            try await presenter.present(
                .runStopped(
                    reason: "Unexpected non-terminal picker choice escaped picker loop."
                )
            )
        }
    }
}

internal struct AppleWriteApprovalConfiguration: Sendable, Hashable {
    var targetPath: String

    static func parse(
        _ arguments: [String]
    ) throws -> Self {
        var targetPath = "agentic-interface-hello.txt"
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--path":
                targetPath = try requireNext(
                    &iterator,
                    after: argument
                )

            default:
                if argument.hasPrefix("--path=") {
                    targetPath = String(
                        argument.dropFirst(
                            "--path=".count
                        )
                    )
                } else if !argument.hasPrefix("-") {
                    targetPath = argument
                } else {
                    throw AgenticInterfaceTestError.unknownArgument(
                        argument
                    )
                }
            }
        }

        return .init(
            targetPath: targetPath
        )
    }
}
