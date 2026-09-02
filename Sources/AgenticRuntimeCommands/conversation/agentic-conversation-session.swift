import Agentic
import AgenticExecution
import AgenticInterfaces
import AgenticModels
import AgenticRuntime
import AgenticWorkspace
import Foundation

package enum AgenticConversationSessionError: Error, LocalizedError {
    case noModelProfiles
    case missingSkills([String])

    package var errorDescription: String? {
        switch self {
        case .noModelProfiles:
            return "The application has no registered model profiles."
        case .missingSkills(let identifiers):
            return "Unknown selected skill(s): \(identifiers.joined(separator: ", "))."
        }
    }
}

package struct AgenticConversationSession {
    package private(set) var snapshot: AgenticConversationSnapshot

    private let runtime: AgenticRuntime
    private let workspace: AgentWorkspace
    private let baseSessionID: String
    private var transcript: [AgentMessage]
    private var nextOrdinal: Int
    private var runInputs: [String: String]
    private var runOutputs: [String: String]

    package init(
        runtime: AgenticRuntime,
        workspacePath: String,
        sessionID: String? = nil
    ) throws {
        let workspace = try AgenticRuntimeWorkspace.resolve(workspacePath)
        let profiles = runtime.profiles.profilesByIdentifier.values.sorted {
            let lhsTitle = $0.title ?? $0.identifier.rawValue
            let rhsTitle = $1.title ?? $1.identifier.rawValue
            if lhsTitle == rhsTitle {
                return $0.identifier.rawValue < $1.identifier.rawValue
            }
            return lhsTitle < rhsTitle
        }

        guard let selectedProfile = profiles.first else {
            throw AgenticConversationSessionError.noModelProfiles
        }

        let skills = runtime.skills.skills_sorted.map { skill in
            let references =
                skill.metadata.tools.required
                + skill.metadata.tools.optional

            return AgenticConversationSkillPresentation(
                id: skill.identifier,
                title: skill.name,
                summary: skill.summary,
                toolNames: references.map(\.name)
            )
        }

        self.runtime = runtime
        self.workspace = workspace
        self.baseSessionID = sessionID ?? UUID().uuidString
        self.transcript = []
        self.nextOrdinal = 1
        self.runInputs = [:]
        self.runOutputs = [:]
        self.snapshot = AgenticConversationSnapshot(
            workspace: workspace.rootURL.path,
            activity: "ready",
            models: profiles.map { profile in
                AgenticConversationModelPresentation(
                    id: profile.identifier,
                    title: profile.title ?? profile.identifier.rawValue,
                    detail: "\(profile.model) · \(profile.adapterIdentifier.rawValue)"
                )
            },
            selectedModelProfileID: selectedProfile.identifier,
            skills: skills,
            hostConsole: .init(
                context: workspace.rootURL.path
            )
        )
    }

    package mutating func selectModel(
        _ identifier: AgentModelProfileIdentifier
    ) {
        snapshot.selectedModelProfileID = identifier
        snapshot.activity = "model selected"
    }

    package mutating func selectSkills(
        _ identifiers: [AgentSkillIdentifier]
    ) {
        snapshot.selectedSkillIDs = identifiers
        snapshot.activity = identifiers.isEmpty
            ? "full tool manifest selected"
            : "skill tool set selected"
    }

    package mutating func setActivity(_ activity: String) {
        snapshot.activity = activity
    }

    @discardableResult
    package mutating func submit(
        _ submission: AgenticConversationSubmission
    ) async throws -> AgentRunResult {
        selectModel(submission.modelProfileID)
        selectSkills(submission.skillIDs)

        let profile = try runtime.profiles.profile(
            submission.modelProfileID
        )
        let adapter = try runtime.adapters.adapter(
            for: profile.adapterIdentifier
        )
        let selection = try runtime.skills.selecting(
            submission.skillIDs
        )

        guard selection.missingIdentifiers.isEmpty else {
            throw AgenticConversationSessionError.missingSkills(
                selection.missingIdentifiers.map(\.rawValue)
            )
        }

        let tools: ToolRegistry
        if submission.skillIDs.isEmpty {
            tools = runtime.tools
        } else {
            let identifiers = selection.loadedSkills.flatMap { skill in
                (
                    skill.metadata.tools.required
                    + skill.metadata.tools.optional
                ).map(\.identifier)
            }
            tools = try runtime.tools.selecting(identifiers)
        }

        let renderedInput = Self.renderedInput(submission)
        let runID = "\(baseSessionID)-turn-\(nextOrdinal)"
        let turnOrdinal = nextOrdinal
        nextOrdinal += 1

        let userMessage = AgentMessage(
            role: .user,
            text: renderedInput
        )
        transcript.append(userMessage)
        snapshot.messages.append(
            .init(
                id: userMessage.id,
                role: .user,
                body: submission.body,
                attachments: submission.contents.map {
                    .content($0)
                }
            )
        )
        snapshot.activity = "invoking \(profile.title ?? profile.model)"

        var requestMessages = [
            AgentMessage(
                role: .system,
                text: Self.systemPrompt(
                    workspace: workspace,
                    skills: selection.loadedSkills
                )
            ),
        ]
        requestMessages.append(contentsOf: transcript)

        let request = AgentRequest(
            model: profile.model,
            messages: requestMessages,
            metadata: [
                "conversation_session_id": baseSessionID,
                "conversation_run_id": runID,
                "model_profile_id": profile.identifier.rawValue,
            ]
        )
        let runner = AgentRunner(
            adapter: adapter,
            configuration: .init(
                maximumIterations: 12,
                responseDelivery: .stream
            ),
            toolRegistry: tools,
            workspace: workspace
        )
        let result = try await runner.run(
            request,
            sessionID: runID
        )

        transcript = result.state.messages.filter {
            $0.role != .system
        }

        let projection = AgenticConversationRunProjection.project(
            result,
            title: "conversation turn \(turnOrdinal)"
        )
        snapshot.hostConsole.runs.append(projection.run)
        snapshot.hostConsole.documents.append(
            contentsOf: projection.documents
        )

        let responseText = result.response?.message.content.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let responseText, !responseText.isEmpty {
            body = responseText
        } else if result.isAwaitingApproval {
            body = "The run is awaiting approval."
        } else if result.isSuspended {
            body = "The run is suspended."
        } else {
            body = "The run completed without assistant text."
        }

        snapshot.messages.append(
            .init(
                id: result.response?.message.id ?? UUID().uuidString,
                role: .assistant,
                body: body,
                attachments: [
                    .run(runID: runID),
                ]
            )
        )
        snapshot.activity = result.isCompleted
            ? "response completed"
            : "response suspended"

        runInputs[runID] = renderedInput
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        runOutputs[runID] = String(
            decoding: try encoder.encode(result),
            as: UTF8.self
        )

        return result
    }

    package mutating func recordFailure(_ error: Error) {
        let body = error.localizedDescription
        snapshot.activity = "model invocation failed"
        snapshot.messages.append(
            .init(
                id: UUID().uuidString,
                role: .assistant,
                body: body
            )
        )
        snapshot.hostConsole.statuses.append(
            .init(
                id: UUID().uuidString,
                kind: .error,
                title: "Conversation run failed",
                summary: "model invocation",
                body: body
            )
        )
    }

    package func input(for runID: String) -> String? {
        runInputs[runID]
    }

    package func output(for runID: String) -> String? {
        runOutputs[runID]
    }

    private static func renderedInput(
        _ submission: AgenticConversationSubmission
    ) -> String {
        var sections = [submission.body]
        for content in submission.contents {
            sections.append(
                "# Attached content: \(content.title)\n\n\(content.body)"
            )
        }
        return sections.joined(separator: "\n\n")
    }

    private static func systemPrompt(
        workspace: AgentWorkspace,
        skills: [AgentSkill]
    ) -> String {
        var sections = [
            "You are operating in an Agentic terminal conversation.",
            "Workspace root: \(workspace.rootURL.path)",
            "Use only the advertised tools and keep all file operations inside the workspace.",
        ]

        if skills.isEmpty {
            sections.append(
                "No skill is selected. The full registered tool manifest is available."
            )
        } else {
            sections.append(
                skills.map(\.contextText).joined(separator: "\n\n")
            )
        }

        return sections.joined(separator: "\n\n")
    }
}
