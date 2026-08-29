import Agentic
import AgenticExecution
import Foundation
import Primitives

extension ToolLoopExecutor {
    func requestWithCurrentState(
        from request: AgentRequest,
        messages: [AgentMessage]
    ) -> AgentRequest {
        AgentRequest(
            model: request.model,
            messages: messages,
            tools: toolDefinitions(
                fallback: request.tools
            ),
            generationConfiguration: request.generationConfiguration,
            metadata: request.metadata
        )
    }

    func toolDefinitions(
        fallback: [AgentToolDefinition]
    ) -> [AgentToolDefinition] {
        let definitions = toolRegistry.definitions

        guard !definitions.isEmpty else {
            return fallback
        }

        return definitions
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
        guard let approvalHandler else {
            return requirement.decision
        }

        return try await approvalHandler.decide(
            on: preflight,
            requirement: requirement
        )
    }

    func executeApprovedToolCall(
        _ toolCall: AgentToolCall
    ) async -> AgentToolResult {
        do {
            return try await toolRegistry.call(
                toolCall,
                workspace: workspace
            )
        } catch {
            return makeToolErrorResult(
                for: toolCall,
                error: error
            )
        }
    }

    func makeDeniedToolResult(
        for toolCall: AgentToolCall,
        preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) -> AgentToolResult {
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
            output: try! JSONToolBridge.encode(payload),
            isError: true
        )
    }

    func makeSkippedToolResult(
        for toolCall: AgentToolCall,
        summary: String = "Skipped explicitly by the operator."
    ) -> AgentToolResult {
        let payload = ToolSkipPayload(
            kind: "tool_skipped",
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            summary: summary
        )

        return AgentToolResult(
            toolCallID: toolCall.id,
            name: toolCall.name,
            output: try! JSONToolBridge.encode(payload),
            isError: false
        )
    }

    func makeToolErrorResult(
        for toolCall: AgentToolCall,
        error: Error
    ) -> AgentToolResult {
        let payload = ToolErrorPayload(
            kind: "tool_error",
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            message: localizedDescription(for: error)
        )

        return AgentToolResult(
            toolCallID: toolCall.id,
            name: toolCall.name,
            output: try! JSONToolBridge.encode(payload),
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

        switch suspension.reason {
        case .approval(let pendingApproval):
            return .awaitingApproval(
                sessionID: checkpoint.id,
                response: response,
                pendingApproval: pendingApproval,
                state: checkpoint.state,
                events: checkpoint.events,
                costRecord: checkpoint.costRecord
            )

        case .user_input(let pendingUserInput):
            return .awaitingUserInput(
                sessionID: checkpoint.id,
                response: response,
                pendingUserInput: pendingUserInput,
                state: checkpoint.state,
                events: checkpoint.events,
                costRecord: checkpoint.costRecord
            )
        }
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
        guard configuration.persistsHistory else {
            return
        }

        guard let historyStore else {
            return
        }

        checkpoint.touch()

        try await historyStore.saveCheckpoint(
            checkpoint
        )
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
        for sink in eventSinks {
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
        for sink in eventSinks {
            try await sink.recordToolCall(
                toolCall
            )
        }
    }

    func recordToolResult(
        _ result: AgentToolResult
    ) async throws {
        for sink in eventSinks {
            try await sink.recordToolResult(
                result
            )
        }
    }

    func recordRunEvent(
        _ event: AgentRunEvent
    ) async throws {
        for sink in eventSinks {
            try await sink.recordRunEvent(
                event
            )
        }
    }
}
