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

package actor AgenticConversationSession:
    AgentRunStateSink
{
    package private(set) var snapshot: AgenticConversationSnapshot

    private let runtime: AgenticRuntime
    private let workspace: AgentWorkspace
    private let baseSessionID: String
    private var transcript: [AgentMessage]
    private var nextOrdinal: Int
    private var runInputs: [String: String]
    private var runOutputs: [String: String]
    private var activeRunID: String?
    private var activeRunTitle: String?
    private var liveRunState: AgentRunStateSnapshot?
    private var liveAssistantText: String?

    package init(
        runtime: AgenticRuntime,
        workspacePath: String,
        sessionID: String? = nil
    ) throws {
        try self.init(
            runtime: runtime,
            workspace: .init(
                path: workspacePath
            ),
            sessionID: sessionID
        )
    }

    package init(
        runtime: AgenticRuntime,
        workspace configuration:
            AgenticRuntimeWorkspaceConfiguration,
        sessionID: String? = nil
    ) throws {
        let workspace = try AgenticRuntimeWorkspace.resolve(
            configuration
        )
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
        self.activeRunID = nil
        self.activeRunTitle = nil
        self.liveRunState = nil
        self.liveAssistantText = nil
        self.snapshot = AgenticConversationSnapshot(
            workspace: workspace.rootURL.path,
            activity: "ready",
            models: profiles.map { profile in
                AgenticConversationModelPresentation(
                    id: profile.identifier,
                    title: profile.title ?? profile.identifier.rawValue,
                    detail: "\(profile.model) · \(profile.adapterIdentifier.rawValue)",
                    supportsStreaming: profile.capabilities.contains(
                        .streaming
                    )
                )
            },
            selectedModelProfileID: selectedProfile.identifier,
            selectedResponseDelivery:
                selectedProfile.capabilities.contains(.streaming)
                    ? .stream
                    : .buffered,
            selectedAutonomyMode: .auto_observe,
            skills: skills,
            hostConsole: .init(
                context: workspace.rootURL.path
            )
        )
    }

    package func selectModel(
        _ identifier: AgentModelProfileIdentifier
    ) {
        snapshot.selectedModelProfileID = identifier

        if let profile = runtime.profiles.profilesByIdentifier[identifier],
           !profile.capabilities.contains(.streaming)
        {
            snapshot.selectedResponseDelivery = .buffered
        }

        snapshot.activity = "model selected"
    }

    package func selectResponseDelivery(
        _ delivery: AgentModelResponseDelivery
    ) {
        if delivery == .stream,
           let profile =
            runtime.profiles.profilesByIdentifier[
                snapshot.selectedModelProfileID
            ],
           !profile.capabilities.contains(.streaming)
        {
            snapshot.selectedResponseDelivery = .buffered
            snapshot.activity = "streaming unavailable for selected model"
            return
        }

        snapshot.selectedResponseDelivery = delivery
        snapshot.activity = "\(delivery.rawValue) response delivery selected"
    }

    package func selectAutonomy(
        _ mode: AutonomyMode
    ) {
        snapshot.selectedAutonomyMode = mode
        snapshot.activity = "\(mode.rawValue) autonomy selected"
    }

    package func selectSkills(
        _ identifiers: [AgentSkillIdentifier]
    ) {
        snapshot.selectedSkillIDs = identifiers
        snapshot.activity = "skills selected"
    }

    package func selectToolExposure(
        _ exposure: AgenticConversationToolExposure
    ) {
        snapshot.selectedToolExposure = exposure
        snapshot.activity = "\(exposure.title.lowercased()) tool exposure selected"
    }

    package func setActivity(_ activity: String) {
        snapshot.activity = activity
    }

    package func setVoiceAvailability(
        _ availability: AgenticConversationVoice.Availability
    ) {
        snapshot.voiceAvailability = availability
    }

    package func setVoiceState(
        _ state: AgenticConversationVoice.State
    ) {
        snapshot.voiceState = state
    }

    package func setVoiceStatus(
        _ status: AgenticConversationVoice.Status?
    ) {
        snapshot.voiceStatus = status
    }

    @discardableResult
    package func submit(
        _ submission: AgenticConversationSubmission
    ) async throws -> AgentRunResult {
        selectModel(submission.modelProfileID)
        selectResponseDelivery(submission.responseDelivery)
        selectAutonomy(submission.autonomyMode)
        selectSkills(submission.skillIDs)
        selectToolExposure(submission.toolExposure)

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

        let toolExposure: AgentToolExposurePolicy
        switch submission.toolExposure {
        case .discovery:
            toolExposure = .discoveryOnly

        case .all:
            toolExposure = .all

        case .skillSeeded:
            toolExposure = .skillSeeded(
                selection.loadedSkills
            )
        }

        let renderedInput = Self.renderedInput(submission)
        let runID = "\(baseSessionID)-turn-\(nextOrdinal)"
        let turnOrdinal = nextOrdinal
        let runTitle = "conversation turn \(turnOrdinal)"
        nextOrdinal += 1
        activeRunID = runID
        activeRunTitle = runTitle
        liveRunState = nil
        liveAssistantText = nil

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
        snapshot.messages.append(
            .init(
                id: "\(runID)-assistant",
                role: .assistant,
                body: "invoking model",
                attachments: [
                    .run(runID: runID),
                ]
            )
        )
        upsertRun(
            .init(
                id: runID,
                title: runTitle,
                state: .active
            )
        )
        snapshot.activity = "invoking \(profile.title ?? profile.model)"

        var requestMessages = [
            AgentMessage(
                role: .system,
                text: Self.systemPrompt(
                    workspace: workspace,
                    skills: selection.loadedSkills,
                    toolExposure: submission.toolExposure
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
                "conversation_input_origin": submission.origin.rawValue,
                "conversation_tool_exposure": submission.toolExposure.rawValue,
                "conversation_response_delivery":
                    snapshot.selectedResponseDelivery.rawValue,
                "conversation_autonomy_mode": submission.autonomyMode.rawValue,
            ]
        )
        let runner = AgentRunner(
            adapter: adapter,
            configuration: .init(
                maximumIterations: 12,
                autonomyMode: submission.autonomyMode,
                toolExposure: toolExposure,
                responseDelivery: snapshot.selectedResponseDelivery
            ),
            toolRegistry: runtime.tools,
            workspace: workspace,
            stateSinks: [
                self,
            ]
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
        upsertRun(
            projection.run
        )
        snapshot.hostConsole.documents.removeAll { document in
            document.runID == runID
        }
        snapshot.hostConsole.documents.append(
            contentsOf: projection.documents
        )

        let responseText = result.response?.message.content.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let responseText, !responseText.isEmpty {
            body = responseText
        } else if let liveAssistantText, !liveAssistantText.isEmpty {
            body = liveAssistantText
        } else if let failure = result.failure {
            body = failure.message
        } else if result.isAwaitingApproval {
            body = "The run is awaiting approval."
        } else if result.isSuspended {
            body = "The run is suspended."
        } else {
            body = "The run completed without assistant text."
        }

        updateAssistant(
            runID: runID,
            body: body
        )
        if let failure = result.failure {
            snapshot.activity = "run failed"
            upsertFailureStatus(
                runID: runID,
                summary: failure.kind.rawValue,
                body: failure.message
            )
        } else {
            snapshot.activity = result.isCompleted
                ? "response completed"
                : "response suspended"
        }

        liveRunState = nil
        liveAssistantText = nil
        activeRunID = nil
        activeRunTitle = nil

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

    package func recordFailure(_ error: Error) {
        let body = error.localizedDescription
        snapshot.activity = "conversation run failed"

        if let runID = activeRunID {
            if liveAssistantText?.isEmpty != false {
                updateAssistant(
                    runID: runID,
                    body: body
                )
            }

            upsertRun(
                .init(
                    id: runID,
                    title: activeRunTitle ?? runID,
                    summary: body,
                    state: .failed,
                    steps: snapshot.hostConsole.runs.first(where: {
                        $0.id == runID
                    })?.steps ?? []
                )
            )
            upsertFailureStatus(
                runID: runID,
                summary: "runtime error",
                body: body
            )
        } else {
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
                    summary: "runtime error",
                    body: body
                )
            )
        }

        liveRunState = nil
        liveAssistantText = nil
        activeRunID = nil
        activeRunTitle = nil
    }

    package func publish(
        _ state: AgentRunStateSnapshot
    ) async {
        liveRunState = state
        activeRunID = state.sessionID

        let partialText = state.partialResponse?.message.content.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let responseText = state.lastResponse?.message.content.text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let partialText, !partialText.isEmpty {
            liveAssistantText = partialText
        } else if let responseText, !responseText.isEmpty {
            liveAssistantText = responseText
        }

        let visibleBody = liveAssistantText
            ?? state.failure?.message
        let projection = AgenticConversationRunProjection.project(
            state,
            title: activeRunTitle ?? state.sessionID
        )

        upsertRun(
            projection.run
        )
        snapshot.hostConsole.documents.removeAll { document in
            document.runID == state.sessionID
        }
        snapshot.hostConsole.documents.append(
            contentsOf: projection.documents
        )

        if let visibleBody,
           !visibleBody.isEmpty
        {
            updateAssistant(
                runID: state.sessionID,
                body: visibleBody
            )
        }

        if let failure = state.failure {
            upsertFailureStatus(
                runID: state.sessionID,
                summary: failure.kind.rawValue,
                body: failure.message
            )
        }

        snapshot.activity = Self.activityTitle(
            for: state
        )
    }

    package func presentationSnapshot(
        now: Date = Date()
    ) -> AgenticConversationSnapshot {
        var presentation = snapshot

        guard let liveRunState else {
            return presentation
        }

        let elapsedEnd: Date
        switch liveRunState.phase {
        case .ready_for_model,
             .receiving_model_response,
             .processing_tool_calls:
            elapsedEnd = now

        case .suspended,
             .awaiting_approval,
             .interrupted,
             .failed,
             .completed:
            elapsedEnd = liveRunState.updatedAt
        }

        let elapsed = max(
            0,
            elapsedEnd.timeIntervalSince(
                liveRunState.startedAt
            )
        )
        presentation.activity = String(
            format: "%@ · %.1fs",
            Self.activityTitle(
                for: liveRunState
            ),
            elapsed
        )
        return presentation
    }

    private func updateAssistant(
        runID: String,
        body: String
    ) {
        guard let index = snapshot.messages.firstIndex(where: { message in
            message.attachments.contains { attachment in
                guard case .run(let attachedRunID) = attachment else {
                    return false
                }
                return attachedRunID == runID
            }
        }) else {
            snapshot.messages.append(
                .init(
                    id: "\(runID)-assistant",
                    role: .assistant,
                    body: body,
                    attachments: [
                        .run(runID: runID),
                    ]
                )
            )
            return
        }

        snapshot.messages[index].body = body
    }

    private func upsertRun(
        _ run: AgenticHostConsoleRunPresentation
    ) {
        if let index = snapshot.hostConsole.runs.firstIndex(where: {
            $0.id == run.id
        }) {
            snapshot.hostConsole.runs[index] = run
        } else {
            snapshot.hostConsole.runs.append(
                run
            )
        }
    }

    private func upsertFailureStatus(
        runID: String,
        summary: String,
        body: String
    ) {
        let id = "\(runID)-failure"
        let status = AgenticHostConsoleStatusPresentation(
            id: id,
            runID: runID,
            kind: .error,
            title: "Conversation run failed",
            summary: summary,
            body: body
        )

        if let index = snapshot.hostConsole.statuses.firstIndex(where: {
            $0.id == id
        }) {
            snapshot.hostConsole.statuses[index] = status
        } else {
            snapshot.hostConsole.statuses.append(
                status
            )
        }
    }

    private static func activityTitle(
        for state: AgentRunStateSnapshot
    ) -> String {
        if state.pendingUserInput != nil {
            return "awaiting user input"
        }

        switch state.phase {
        case .ready_for_model:
            return "invoking model"

        case .receiving_model_response:
            return "streaming"

        case .processing_tool_calls:
            return "processing tools"

        case .suspended:
            return "suspended"

        case .awaiting_approval:
            return "awaiting approval"

        case .interrupted:
            return "interrupted"

        case .failed:
            return "failed"

        case .completed:
            return "completed"
        }
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
            let heading: String

            switch content.kind {
            case .pasted:
                heading = "Pasted content"

            case .transcribed:
                heading = "Transcribed content"
            }

            sections.append(
                "# \(heading): \(content.title)\n\n\(content.body)"
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private static func systemPrompt(
        workspace: AgentWorkspace,
        skills: [AgentSkill],
        toolExposure: AgenticConversationToolExposure
    ) -> String {
        var sections = [
            "You are operating in an Agentic terminal conversation.",
            "Workspace root: \(workspace.rootURL.path)",
            "Use only the advertised tools and keep all file operations inside the workspace.",
        ]

        if !skills.isEmpty {
            sections.append(
                skills.map(\.contextText).joined(separator: "\n\n")
            )
        }

        switch toolExposure {
        case .discovery:
            sections.append(
                "Tool exposure is discovery-only. Use find_tools to discover registered capabilities before calling them."
            )

        case .all:
            sections.append(
                "All registered model-facing tools are exposed immediately."
            )

        case .skillSeeded:
            if skills.isEmpty {
                sections.append(
                    "No skill tools are currently seeded. Use find_tools to discover registered capabilities."
                )
            } else {
                sections.append(
                    "Tools referenced by selected skills are exposed immediately. Use find_tools to discover additional registered capabilities."
                )
            }
        }

        return sections.joined(separator: "\n\n")
    }
}