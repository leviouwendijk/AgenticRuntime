import AgenticExecution
import AgenticIO
import AgenticRuntime
import AgenticWorkspace
import Agentic
import AgenticAWS
import AgenticInterfaces
import Foundation

enum AWSRefactorApprovalTestCase {
    static func make() -> AgenticInterfaceTestCase {
        .init(
            id: "aws-refactor",
            summary: "Create aws-test.swift, let Claude read it, then stage an edit_file refactor approval."
        ) { arguments in
            try await run(
                arguments
            )
        }
    }

    static func run(
        _ arguments: [String]
    ) async throws {
        let configuration = try AWSRefactorApprovalConfiguration.parse(
            arguments
        )
        let workspaceRoot = try AgenticInterfaceTestEnvironment.workspaceRoot()
        let workspace = try AgentWorkspace(
            root: workspaceRoot
        )

        try AgenticInterfaceTestEnvironment.writeWorkspaceFile(
            AWSRefactorFixture.content,
            to: configuration.targetPath
        )

        let editPolicy = EditFilePolicy.bounded(
            rootID: .project,
            path: configuration.targetPath,
            requiredOperations: [
                .insert_lines,
                .replace_lines,
            ],
            insertionPositions: [
                5,
            ],
            replacementRanges: [
                (11, 16),
                (26, 31),
                (41, 46),
            ]
        )

        var registry = ToolRegistry()
        try registry.register {
            ReadFileTool()
            EditFileTool(
                policy: editPolicy
            )
        }

        let historyStore = FileHistoryStore(
            sessionsdir: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "agentic-interface-aws-refactor-\(UUID().uuidString)",
                    isDirectory: true
                )
        )

        let presenter = AgenticInterfaceRuntimeFactory.presenter()

        let picker = TestFlowApprovalPicker(
            interaction: AgenticInterfaceTestEnvironment.interaction,
            presenter: presenter
        )

        print(
            "bedrock model: \(configuration.model)"
        )

        let adapter = try AgenticInterfaceRuntimeFactory.bedrockAdapter(
            defaultModelIdentifier: configuration.model,
            metadata: [
                "source": "aginttest",
                "test_case": "aws-refactor",
            ]
        )

        // let modelIdentifier = try await AWSBedrockSonnetResolver.resolve(
        //     explicitModelIdentifier: configuration.model,
        //     modelMatch: configuration.modelMatch
        // )

        // print(
        //     "resolved bedrock model: \(modelIdentifier)"
        // )

        // let adapter = try BedrockModelAdapter.resolve(
        //     defaultModelIdentifier: modelIdentifier,
        //     metadata: [
        //         "source": "aginttest",
        //         "test_case": "aws-refactor",
        //         "model_resolved_by": configuration.model == nil ? "bedrock_list" : "explicit"
        //     ]
        // )

        let runner = AgentRunner(
            adapter: adapter,
            configuration: .init(
                maximumIterations: 12,
                autonomyMode: .auto_observe,
                historyPersistenceMode: .checkpointmutation,
                responseDelivery: .stream
            ),
            toolRegistry: registry,
            workspace: workspace,
            historyStore: historyStore
        )


        let prompt = """
        Refactor \(configuration.targetPath).
        1. First call read_file for \(configuration.targetPath) with includeLineNumbers true. Do not ask me to paste the file.
        2. After reading the file, call edit_file exactly once.
        3. The edit_file call must include at least one insert_lines operation.
        4. Use insert_lines at position 5 to add a small private helper inside AWSFormatter, near the top of the struct after public init().
        5. In the same edit_file call, use replace_lines to replace one complete trimming block with calls to that helper.
        6. Preserve all public function names and return formats.
        7. Do not use replace_line for multi-line content.
        8. For insert_lines, include position and lines.
        9. For replace_lines, include range and lines.
        10. For delete_lines, include range.
        11. Do not include expected, expectedLines, or read_file display gutters. The runtime derives exact guard content from the current raw file.
        12. The permitted replace_lines ranges are full original trimming blocks only: 11...16, 26...31, or 41...46.

        Refactor request:
        Extract the repeated string trimming logic into one private helper and update at least one complete trimming site to use it. Keep the change small and reviewable.
        """

        // let prompt = """
        // Refactor \(configuration.targetPath).

        // You must use tools.

        // Tool-call discipline:
        // 1. Emit exactly one tool call per assistant response.
        // 2. Never emit a second tool call in the same assistant response.
        // 3. After any tool result, wait for the next model turn before proposing another tool call.
        // 4. After one successful edit_file result, stop calling tools and briefly summarize what changed.

        // Required sequence:
        // 1. First call read_file for \(configuration.targetPath) with includeLineNumbers true. Do not ask me to paste the file.
        // 2. After reading the file, call edit_file exactly once.
        // 3. The edit_file call must include at least one insert_lines operation.
        // 4. Use insert_lines to add a small private helper inside AWSFormatter, near the top of the struct after public init().
        // 5. In the same edit_file call, use replace_first, replace_unique, or replace_lines to route repeated trimming logic through that helper.
        // 6. Preserve all public function names and return formats.
        // 7. Use replace_line only when content is exactly one logical line with no newline characters.
        // 8. For insert_lines, include position and lines.
        // 9. For replace_lines, include range and lines.
        // 10. For delete_lines, include range.
        // 11. Do not include expected, expectedLines, or read_file display gutters. The runtime derives exact guard content from the current raw file.

        // Refactor request:
        // Extract the repeated string trimming logic into one private helper and update at least one repeated trimming site to use it. Keep the change small and reviewable.
        // """

        try await presenter.present(
            .runStarted(
                prompt: prompt
            )
        )

        let initialResult = try await runner.run(
            AgentRequest(
                messages: [
                    .init(
                        role: .system,
                        text: """
                        Your single edit_file call must include at least one insert_lines operation.
                        Use insert_lines at position 5 to add a private helper inside the existing type.
                        Use replace_lines only for existing code updates.
                        For replace_lines, replace one complete original trimming block only: 11...16, 26...31, or 41...46.
                        Do not use replace_line for multi-line content.
                        For replace_line, content must be exactly one logical line with no newline characters.
                        For insert_lines operations, include position and lines.
                        For replace_lines operations, include range and lines.
                        For delete_lines operations, include range.
                        Never include expected or expectedLines; edit_file derives guards from the current raw file.
                        After one successful edit_file result, stop calling tools and summarize.
                        Make one small reviewable edit.
                        """
                        // text: """
                        // You are a precise Swift refactoring agent.

                        // Use read_file before edit_file when the file content is not already in the prompt.
                        // Emit at most one tool call in each assistant response.
                        // Do not invent file contents.
                        // Prefer read_file with includeLineNumbers true before line-based edits.
                        // read_file.content is raw source text.
                        // read_file.display may contain human-facing line numbers.
                        // Do not copy line-number display gutters into edit_file.
                        // Your single edit_file call must include at least one insert_lines operation.
                        // Use insert_lines to add a private helper inside the existing type.
                        // Use replace_first, replace_unique, or replace_lines for existing code updates.
                        // Do not use replace_line for multi-line content.
                        // For replace_line, content must be exactly one logical line with no newline characters.
                        // For insert_lines operations, include position and lines.
                        // For replace_lines operations, include range and lines.
                        // For delete_lines operations, include range.
                        // Never include expected or expectedLines; edit_file derives guards from the current raw file.
                        // After one successful edit_file result, stop calling tools and summarize.
                        // Make one small reviewable edit.
                        // """
                    ),
                    .init(
                        role: .user,
                        text: prompt
                    )
                ],
                generationConfiguration: .init(
                    maxOutputTokens: configuration.maxOutputTokens,
                    temperature: configuration.temperature
                )
            )
        )

        guard let pendingApproval = initialResult.pendingApproval else {
            try await presenter.present(
                initialResult
            )

            throw AWSRefactorApprovalTestError.expectedApproval
        }

        guard pendingApproval.toolCall.name == EditFileTool.identifier.rawValue else {
            try await presenter.present(
                initialResult
            )

            throw AWSRefactorApprovalTestError.expectedEditApproval(
                pendingApproval.toolCall.name
            )
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
                title: "AWS Bedrock refactor awaiting approval"
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
                approvalDecision: ApprovalDecision.approved,
                metadata: [
                    "summary": "approved AWS refactor from aginttest terminal interface"
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
                approvalDecision: ApprovalDecision.denied,
                metadata: [
                    "summary": "denied AWS refactor from aginttest terminal interface"
                ]
            )

            try await presenter.present(
                resumed
            )

        case .skip:
            try await presenter.present(
                .approvalDecision(
                    .skipped
                )
            )

            let resumed = try await runner.resume(
                sessionID: initialResult.sessionID,
                approvalDecision: .skipped,
                metadata: [
                    "summary": "skipped AWS refactor from aginttest terminal interface"
                ]
            )

            try await presenter.present(
                resumed
            )

        case .stop_run:
            try await presenter.present(
                .runStopped(
                    reason: "User stopped the AWS refactor run from the approval picker."
                )
            )

        case .inspect_details,
             .show_diff:
            try await presenter.present(
                .runStopped(
                    reason: "Unexpected non-terminal picker choice escaped picker loop."
                )
            )
        }
    }
}

struct AWSRefactorApprovalConfiguration: Sendable, Hashable {
    static let defaultModel = "eu.amazon.nova-micro-v1:0"

    var targetPath: String
    var model: String
    var maxOutputTokens: Int
    var temperature: Double

    static func parse(
        _ arguments: [String]
    ) throws -> Self {
        var targetPath = "aws-test.swift"
        var model = ProcessInfo.processInfo.environment["AGENTIC_BEDROCK_MODEL"] ?? Self.defaultModel
        var maxOutputTokens = 1_600
        var temperature = 0.0

        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--path":
                targetPath = try requireNext(
                    &iterator,
                    after: argument
                )

            case "--model":
                model = try requireNext(
                    &iterator,
                    after: argument
                )

            case "--max-output-tokens":
                let value = try requireNext(
                    &iterator,
                    after: argument
                )

                guard let parsed = Int(value) else {
                    throw AgenticInterfaceTestError.invalidInteger(
                        argument: argument,
                        value: value
                    )
                }

                maxOutputTokens = parsed

            case "--temperature":
                let value = try requireNext(
                    &iterator,
                    after: argument
                )

                guard let parsed = Double(value) else {
                    throw AgenticInterfaceTestError.unknownArgument(
                        "\(argument) \(value)"
                    )
                }

                temperature = parsed

            default:
                if argument.hasPrefix("--path=") {
                    targetPath = String(
                        argument.dropFirst(
                            "--path=".count
                        )
                    )
                } else if argument.hasPrefix("--model=") {
                    model = String(
                        argument.dropFirst(
                            "--model=".count
                        )
                    )
                } else if argument.hasPrefix("--max-output-tokens=") {
                    let value = String(
                        argument.dropFirst(
                            "--max-output-tokens=".count
                        )
                    )

                    guard let parsed = Int(value) else {
                        throw AgenticInterfaceTestError.invalidInteger(
                            argument: "--max-output-tokens",
                            value: value
                        )
                    }

                    maxOutputTokens = parsed
                } else if argument.hasPrefix("--temperature=") {
                    let value = String(
                        argument.dropFirst(
                            "--temperature=".count
                        )
                    )

                    guard let parsed = Double(value) else {
                        throw AgenticInterfaceTestError.unknownArgument(
                            "--temperature=\(value)"
                        )
                    }

                    temperature = parsed
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
            targetPath: targetPath,
            model: model,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature
        )
    }
}

private enum AWSRefactorApprovalTestError: Error, Sendable, LocalizedError {
    case expectedApproval
    case expectedEditApproval(String)

    var errorDescription: String? {
        switch self {
        case .expectedApproval:
            return "Expected the AWS refactor flow to suspend for edit_file approval, but it did not."

        case .expectedEditApproval(let toolName):
            return "Expected approval for edit_file, but the pending tool was '\(toolName)'."
        }
    }
}

enum AWSRefactorFixture {
    static let content = """
    import Foundation

    public struct AWSFormatter {
        public init() {}

        public func renderUser(
            name: String,
            city: String,
            score: Int
        ) -> String {
            let trimmedName = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let trimmedCity = city.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            return "user=\\(trimmedName); city=\\(trimmedCity); score=\\(score)"
        }

        public func renderDog(
            name: String,
            breed: String,
            age: Int
        ) -> String {
            let trimmedName = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let trimmedBreed = breed.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            return "dog=\\(trimmedName); breed=\\(trimmedBreed); age=\\(age)"
        }

        public func renderAppointment(
            client: String,
            topic: String,
            hour: Int
        ) -> String {
            let trimmedClient = client.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let trimmedTopic = topic.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            return "client=\\(trimmedClient); topic=\\(trimmedTopic); hour=\\(hour)"
        }
    }

    """
}
