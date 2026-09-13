import Agentic
import AgenticExecution
import AgenticRecovery
import Foundation
import Primitives

struct AgentToolExecutionOutcome {
    let result: AgentToolResult
    let recovery: Recovery.Record?
}

private struct AgentToolActiveRecovery {
    let incident: Recovery.Incident
    let plan: Recovery.Plan
    let decision: Recovery.Decision
    var attempts: [Recovery.Attempt]
    var lastMessage: String

    init?(
        error: any Error,
        preflight: ToolPreflight,
        policy: Recovery.Policy?
    ) {
        guard
            preflight.risk == .observe,
            let error = error as? AgentToolCallError,
            error.failure.phase == .call,
            let incident = error.failure.incident,
            incident.retrySafety == .safe,
            Self.allowsExactRetry(
                effectState: incident.effectState
            ),
            let plan = policy?.plan(
                for: incident
            ),
            let step = plan.steps.first,
            step.action == .retry_same_operation
        else {
            return nil
        }

        self.incident = incident
        self.plan = plan
        self.decision = Recovery.Decision(
            step: step
        )
        self.attempts = []
        self.lastMessage = error.failure.message
    }

    func record(
        outcome: Recovery.Outcome
    ) -> Recovery.Record {
        Recovery.Record(
            incident: incident,
            plan: plan,
            attempts: attempts,
            outcome: outcome
        )
    }

    func accepts(
        _ error: any Error
    ) -> Bool {
        guard
            let error = error as? AgentToolCallError,
            error.failure.phase == .call,
            let incident = error.failure.incident,
            incident.kind == self.incident.kind,
            incident.stage == self.incident.stage,
            incident.scope == self.incident.scope,
            incident.retrySafety == .safe,
            Self.allowsExactRetry(
                effectState: incident.effectState
            )
        else {
            return false
        }

        return true
    }

    private static func allowsExactRetry(
        effectState: Recovery.EffectState
    ) -> Bool {
        switch effectState {
        case .none,
             .not_applied:
            return true

        case .applied,
             .unknown:
            return false
        }
    }
}

extension ToolLoopExecutor {
    func requestWithCurrentState(
        from request: AgentRequest,
        messages: [AgentMessage]
    ) async throws -> AgentRequest {
        let definitions = try await toolDefinitions(
            fallback: request.tools
        )

        return AgentRequest(
            messages: messages,
            tools: definitions,
            generationConfiguration: request.generationConfiguration,
            responseFormat: request.responseFormat,
            invocationoptions: request.invocationoptions,
            metadata: request.metadata
        )
    }

    func toolDefinitions(
        fallback: [AgentToolDefinition]
    ) async throws -> [AgentToolDefinition] {
        guard !tooling.registry.isEmpty else {
            return fallback
        }

        return try await toolExposure.definitions(
            in: tooling.registry
        )
    }

    func toolCalls(
        in message: AgentMessage
    ) -> [AgentToolCall] {
        message.content.blocks.compactMap { block in
            guard case .tool_call(let value) = block else {
                return nil
            }

            return value
        }
    }

    func appendToolResultBlock(
        _ block: AgentContentBlock,
        to state: inout AgentLoopState
    ) {
        if configuration.appendToolResultsAsMessages {
            state.messages.append(
                AgentMessage(
                    role: .tool,
                    content: .init(
                        blocks: [block]
                    )
                )
            )
            return
        }

        if let last = state.messages.last,
           last.role == .tool {
            var updated = last
            updated.content.blocks.append(
                block
            )
            state.messages.removeLast()
            state.messages.append(
                updated
            )
            return
        }

        state.messages.append(
            AgentMessage(
                role: .tool,
                content: .init(
                    blocks: [block]
                )
            )
        )
    }

    func resolveApprovalDecision(
        for preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) async throws -> ApprovalDecision {
        guard let approvalHandler = tooling.approvalHandler else {
            return requirement.decision
        }

        return try await approvalHandler.decide(
            on: preflight,
            requirement: requirement
        )
    }

    func executeApprovedToolCall(
        _ toolCall: AgentToolCall,
        preflight: ToolPreflight
    ) async throws -> AgentToolExecutionOutcome {
        do {
            return AgentToolExecutionOutcome(
                result: try await tooling.registry.call(
                    toolCall,
                    workspace: tooling.workspace
                ),
                recovery: nil
            )
        } catch {
            guard var recovery = AgentToolActiveRecovery(
                error: error,
                preflight: preflight,
                policy: configuration.recovery
            ) else {
                return AgentToolExecutionOutcome(
                    result: try makeToolErrorResult(
                        for: toolCall,
                        error: error
                    ),
                    recovery: nil
                )
            }

            var lastError: any Error = error

            while let permit = recovery.decision.limit.nextAttempt(
                after: UInt(
                    recovery.attempts.count
                )
            ) {
                do {
                    let result = try await tooling.registry.call(
                        toolCall,
                        workspace: tooling.workspace
                    )

                    recovery.attempts.append(
                        Recovery.Attempt(
                            number: permit.number,
                            action: recovery.decision.action,
                            outcome: .recovered
                        )
                    )

                    return AgentToolExecutionOutcome(
                        result: result,
                        recovery: recovery.record(
                            outcome: .recovered
                        )
                    )
                } catch {
                    lastError = error
                    let message = localizedDescription(
                        for: error
                    )

                    recovery.attempts.append(
                        Recovery.Attempt(
                            capturing: error,
                            number: permit.number,
                            action: recovery.decision.action,
                            outcome: .failed,
                            message: message
                        )
                    )
                    recovery.lastMessage = message

                    guard recovery.accepts(error) else {
                        return AgentToolExecutionOutcome(
                            result: try makeToolErrorResult(
                                for: toolCall,
                                error: error
                            ),
                            recovery: recovery.record(
                                outcome: .failed
                            )
                        )
                    }
                }
            }

            return AgentToolExecutionOutcome(
                result: try makeToolErrorResult(
                    for: toolCall,
                    error: lastError
                ),
                recovery: recovery.record(
                    outcome: .exhausted
                )
            )
        }
    }

    func makeDeniedToolResult(
        for toolCall: AgentToolCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) throws -> AgentToolResult {
        let payload = ToolDenialPayload(
            kind: "tool_denied",
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            requirement: requirement.rawValue,
            summary: preflight.summary
        )

        return AgentToolResult(
            toolCallID: toolCall.id,
            name: toolCall.name,
            output: try JSONToolBridge.encode(payload),
            isError: true
        )
    }

    func makeSkippedToolResult(
        for toolCall: AgentToolCall,
        summary: String = "Skipped explicitly by the operator."
    ) throws -> AgentToolResult {
        let payload = ToolSkipPayload(
            kind: "tool_skipped",
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            summary: summary
        )

        return AgentToolResult(
            toolCallID: toolCall.id,
            name: toolCall.name,
            output: try JSONToolBridge.encode(payload),
            isError: false
        )
    }

    func makeToolErrorResult(
        for toolCall: AgentToolCall,
        error: Error
    ) throws -> AgentToolResult {
        let payload = ToolErrorPayload(
            kind: "tool_error",
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            message: localizedDescription(for: error)
        )

        return AgentToolResult(
            toolCallID: toolCall.id,
            name: toolCall.name,
            output: try JSONToolBridge.encode(payload),
            isError: true
        )
    }

    func suspendedResult(
        from checkpoint: AgentHistoryCheckpoint
    ) throws -> AgentRunResult {
        guard let response = checkpoint.lastResponse else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without last response"
            )
        }

        guard let suspension = checkpoint.resolvedSuspension else {
            throw AgentHistoryError.corruptedCheckpoint(
                "suspended checkpoint without suspension payload"
            )
        }

        return .suspended(
            sessionID: checkpoint.id,
            response: response,
            suspension: suspension,
            state: checkpoint.state,
            events: checkpoint.events,
            toolUses: checkpoint.resolvedToolUses,
            costRecord: checkpoint.costRecord
        )
    }

    func suspendForUserInput(
        _ toolCall: AgentToolCall,
        checkpoint: inout AgentHistoryCheckpoint
    ) async throws -> ToolProcessingOutcome {
        try await recordToolCall(
            toolCall
        )

        let input = try JSONToolBridge.decode(
            ClarifyWithUserToolInput.self,
            from: toolCall.input
        )
        let pendingUserInput = input.pendingUserInput
        let suspension = AgentSuspension.user_input(
            pendingUserInput,
            metadata: [
                "toolCallID": toolCall.id,
                "toolName": toolCall.name
            ]
        )

        checkpoint.suspend(
            suspension
        )

        try await appendRunEvent(
            .init(
                kind: .pending_user_input,
                iteration: checkpoint.state.iteration,
                toolCallID: toolCall.id,
                toolName: toolCall.name,
                summary: pendingUserInput.prompt
            ),
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )

        return .result(
            try suspendedResult(
                from: checkpoint
            )
        )
    }

    func normalizedUserInputAnswer(
        _ answer: UserInputAnswer,
        for pendingUserInput: PendingUserInput
    ) throws -> UserInputAnswer {
        switch (pendingUserInput.input, answer) {
        case (.text(let spec), .text(let value)):
            return .text(
                try normalizedTextAnswer(
                    value,
                    validation: spec.validation
                )
            )

        case (.single_choice(let spec), .single_choice(let value)):
            return .single_choice(
                try normalizedSingleChoiceAnswer(
                    value,
                    spec: spec
                )
            )

        case (.multi_choice(let spec), .multi_choice(let value)):
            return .multi_choice(
                try normalizedMultiChoiceAnswer(
                    value,
                    spec: spec
                )
            )

        case (.confirmation, .confirmation(let value)):
            return .confirmation(
                value
            )

        case (.form(let spec), .form(let value)):
            return .form(
                try normalizedFormAnswer(
                    value,
                    spec: spec
                )
            )

        default:
            throw AgentHistoryError.invalidUserInput(
                "Answer kind does not match pending input kind."
            )
        }
    }

    func normalizedTextAnswer(
        _ value: String,
        validation: UserInputValidation?
    ) throws -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let validation = validation ?? .init()

        if validation.required,
           trimmed.isEmpty {
            throw AgentHistoryError.emptyUserInput
        }

        if let minimumLength = validation.minimumLength,
           trimmed.count < minimumLength {
            throw AgentHistoryError.invalidUserInput(
                "Text answer must contain at least \(minimumLength) character(s)."
            )
        }

        if let maximumLength = validation.maximumLength,
           trimmed.count > maximumLength {
            throw AgentHistoryError.invalidUserInput(
                "Text answer must contain at most \(maximumLength) character(s)."
            )
        }

        return trimmed
    }

    func normalizedSingleChoiceAnswer(
        _ answer: SingleChoiceUserInputAnswer,
        spec: SingleChoiceUserInput
    ) throws -> SingleChoiceUserInputAnswer {
        switch answer {
        case .choice(let id):
            let id = id.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !id.isEmpty else {
                throw AgentHistoryError.emptyUserInput
            }

            guard spec.choices.contains(where: { $0.id == id }) else {
                throw AgentHistoryError.invalidUserInput(
                    "Unknown choice id '\(id)'."
                )
            }

            return .choice(
                id
            )

        case .custom(let value):
            guard spec.allowsCustomValue else {
                throw AgentHistoryError.invalidUserInput(
                    "Custom values are not allowed for this single-choice input."
                )
            }

            let value = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !value.isEmpty else {
                throw AgentHistoryError.emptyUserInput
            }

            return .custom(
                value
            )
        }
    }

    func normalizedMultiChoiceAnswer(
        _ answer: MultiChoiceUserInputAnswer,
        spec: MultiChoiceUserInput
    ) throws -> MultiChoiceUserInputAnswer {
        let knownChoiceIDs = Set(
            spec.choices.map(\.id)
        )
        var seen: Set<String> = []
        var choiceIDs: [String] = []

        for rawID in answer.choiceIDs {
            let id = rawID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !id.isEmpty else {
                continue
            }

            guard knownChoiceIDs.contains(id) else {
                throw AgentHistoryError.invalidUserInput(
                    "Unknown choice id '\(id)'."
                )
            }

            guard !seen.contains(id) else {
                continue
            }

            seen.insert(
                id
            )
            choiceIDs.append(
                id
            )
        }

        if choiceIDs.count < spec.minimumSelectionCount {
            throw AgentHistoryError.invalidUserInput(
                "Expected at least \(spec.minimumSelectionCount) selected choice(s)."
            )
        }

        if let maximumSelectionCount = spec.maximumSelectionCount,
           choiceIDs.count > maximumSelectionCount {
            throw AgentHistoryError.invalidUserInput(
                "Expected at most \(maximumSelectionCount) selected choice(s)."
            )
        }

        return .init(
            choiceIDs: choiceIDs
        )
    }

    func normalizedFormAnswer(
        _ answer: FormUserInputAnswer,
        spec: FormUserInput
    ) throws -> FormUserInputAnswer {
        let knownFieldIDs = Set(
            spec.fields.map(\.id)
        )

        for key in answer.values.keys where !knownFieldIDs.contains(key) {
            throw AgentHistoryError.invalidUserInput(
                "Unknown form field id '\(key)'."
            )
        }

        var values: [String: String] = [:]

        for field in spec.fields {
            let rawValue = answer.values[field.id]
                ?? field.defaultText
                ?? ""

            let normalized = try normalizedTextAnswer(
                rawValue,
                validation: field.validation
            )

            if !normalized.isEmpty {
                values[field.id] = normalized
            }
        }

        return .init(
            values: values
        )
    }

    func localizedDescription(
        for error: Error
    ) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(
            describing: error
        )
    }

    func compactIfNeeded(
        _ checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        guard let strategy = configuration.compactionStrategy else {
            return
        }

        guard checkpoint.phase == .ready_for_model else {
            return
        }

        let compactor = AgentCompactor(
            strategy: strategy
        )

        guard let compacted = compactor.compact(
            checkpoint: &checkpoint
        ) else {
            return
        }

        let event = AgentRunEvent(
            kind: .compaction,
            iteration: checkpoint.state.iteration,
            messageID: compacted.summaryMessageID,
            summary: "compacted \(compacted.replacedMessageCount) earlier message(s)"
        )

        try await appendRunEvent(
            event,
            to: &checkpoint
        )

        try await saveCheckpoint(
            &checkpoint
        )
    }

    func saveCheckpoint(
        _ checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        checkpoint.exposedToolIdentifiers = try await toolExposure.identifiers(
            in: tooling.registry
        )
        checkpoint.touch()

        await publishRunState(
            checkpoint
        )

        guard configuration.persistsHistory else {
            return
        }

        guard let historyStore = recording.historyStore else {
            return
        }

        try await historyStore.saveCheckpoint(
            checkpoint
        )
    }

    func publishRunState(
        _ checkpoint: AgentHistoryCheckpoint
    ) async {
        guard !recording.stateSinks.isEmpty else {
            return
        }

        let snapshot = AgentRunStateSnapshot(
            checkpoint: checkpoint
        )

        for sink in recording.stateSinks {
            await sink.publish(
                snapshot
            )
        }
    }

    func appendRunEvent(
        _ event: AgentRunEvent,
        to checkpoint: inout AgentHistoryCheckpoint
    ) async throws {
        checkpoint.events.append(
            event
        )

        try await recordRunEvent(
            event
        )
    }

    func recordMessage(
        _ message: AgentMessage
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordMessage(
                message
            )
        }
    }

    func recordMessages(
        _ messages: [AgentMessage]
    ) async throws {
        for message in messages {
            try await recordMessage(
                message
            )
        }
    }

    func recordToolCall(
        _ toolCall: AgentToolCall
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordToolCall(
                toolCall
            )
        }
    }

    func recordToolResult(
        _ result: AgentToolResult
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordToolResult(
                result
            )
        }
    }

    func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws {
        for sink in recording.eventSinks {
            try await sink.recordRunEvent(
                event
            )
        }
    }
}
