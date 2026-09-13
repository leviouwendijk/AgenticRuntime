import Agentic
import AgenticExecution
import AgenticRecovery
import Foundation
import Primitives

struct AgentToolExecutionOutcome {
    let result: AgentToolResult
    let recovery: Recovery.Record?
}

private enum AgentToolRecoveryError:
    Error,
    LocalizedError
{
    case reconciliation_unsupported
    case reconciliation_unresolved
    case applied_without_output
    case preflight_changed
    case recovery_exhausted
    case action_unsupported(Recovery.Action)

    var errorDescription: String? {
        switch self {
        case .reconciliation_unsupported:
            return "Tool does not support reconciliation for the classified failure."

        case .reconciliation_unresolved:
            return "Tool reconciliation could not determine whether the operation was applied."

        case .applied_without_output:
            return "Tool reconciliation confirmed the operation was applied but could not reconstruct the tool output."

        case .preflight_changed:
            return "Tool preflight changed after reconciliation; retry requires fresh approval."

        case .recovery_exhausted:
            return "Tool recovery exhausted its authored mechanical recovery plan."

        case .action_unsupported(let action):
            return "Runtime does not mechanically execute recovery action '\(action.rawValue)'."
        }
    }
}

private struct AgentToolActiveRecovery {
    let incident: Recovery.Incident
    let plan: Recovery.Plan
    var failure: AgentToolCallFailure
    var attempts: [Recovery.Attempt]
    var state: Recovery.State
    var stepIndex: Int
    var completedAttemptsInStep: UInt

    init?(
        error: any Error,
        policy: Recovery.Policy?
    ) {
        guard
            let error = error as? AgentToolCallError,
            error.failure.phase == .call,
            let incident = error.failure.incident,
            let plan = policy?.plan(
                for: incident
            ),
            let first = plan.steps.first,
            Self.allows(
                first.action,
                state: incident.state
            )
        else {
            return nil
        }

        self.incident = incident
        self.plan = plan
        self.failure = error.failure
        self.attempts = []
        self.state = incident.state
        self.stepIndex = 0
        self.completedAttemptsInStep = 0
    }

    var decision: Recovery.Decision? {
        guard plan.steps.indices.contains(stepIndex) else {
            return nil
        }

        return Recovery.Decision(
            step: plan.steps[stepIndex]
        )
    }

    mutating func advance(
        to state: Recovery.State
    ) {
        self.state = state
        stepIndex += 1
        completedAttemptsInStep = 0
    }

    mutating func absorb(
        _ error: any Error
    ) -> Bool {
        guard
            let error = error as? AgentToolCallError,
            error.failure.phase == .call,
            let incident = error.failure.incident,
            incident.kind == self.incident.kind,
            incident.stage == self.incident.stage,
            incident.scope == self.incident.scope
        else {
            return false
        }

        failure = error.failure
        state = incident.state
        return true
    }

    func record(
        outcome: Recovery.Outcome
    ) -> Recovery.Record {
        Recovery.Record(
            incident: incident,
            plan: plan,
            attempts: attempts,
            state: state,
            outcome: outcome
        )
    }

    static func allows(
        _ action: Recovery.Action,
        state: Recovery.State
    ) -> Bool {
        switch action {
        case .reconcile:
            return state.effect == .unknown
                && state.retry == .requires_reconciliation

        case .retry_same_operation:
            return state.retry == .safe
                && (
                    state.effect == .none
                    || state.effect == .not_applied
                )

        default:
            return false
        }
    }
}

private func isMutationRisk(
    _ risk: ActionRisk
) -> Bool {
    switch risk {
    case .boundedmutate,
         .privileged:
        return true

    case .observe,
         .forbidden:
        return false
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

            while let decision = recovery.decision {
                guard AgentToolActiveRecovery.allows(
                    decision.action,
                    state: recovery.state
                ) else {
                    let recoveryError =
                        AgentToolRecoveryError.action_unsupported(
                            decision.action
                        )

                    return AgentToolExecutionOutcome(
                        result: try makeToolErrorResult(
                            for: toolCall,
                            error: recoveryError
                        ),
                        recovery: recovery.record(
                            outcome: .failed
                        )
                    )
                }

                guard let permit = decision.limit.nextAttempt(
                    after: recovery.completedAttemptsInStep
                ) else {
                    let recoveryError =
                        AgentToolRecoveryError.recovery_exhausted

                    return AgentToolExecutionOutcome(
                        result: try makeToolErrorResult(
                            for: toolCall,
                            error: recoveryError
                        ),
                        recovery: recovery.record(
                            outcome: .exhausted
                        )
                    )
                }

                recovery.completedAttemptsInStep += 1

                switch decision.action {
                case .reconcile:
                    do {
                        guard let reconciliation = try await tooling.registry.reconcile(
                            toolCall,
                            failure: recovery.failure,
                            context: AgentToolExecutionContext(
                                workspace: tooling.workspace
                            )
                        ) else {
                            let recoveryError =
                                AgentToolRecoveryError.reconciliation_unsupported

                            recovery.attempts.append(
                                Recovery.Attempt(
                                    capturing: recoveryError,
                                    number: permit.number,
                                    action: decision.action,
                                    state: recovery.state
                                )
                            )

                            return AgentToolExecutionOutcome(
                                result: try makeToolErrorResult(
                                    for: toolCall,
                                    error: recoveryError
                                ),
                                recovery: recovery.record(
                                    outcome: .failed
                                )
                            )
                        }

                        let state = reconciliation.state

                        recovery.attempts.append(
                            Recovery.Attempt(
                                number: permit.number,
                                action: decision.action,
                                status: .succeeded,
                                state: state
                            )
                        )
                        recovery.state = state

                        switch reconciliation {
                        case .applied(let result):
                            return AgentToolExecutionOutcome(
                                result: result,
                                recovery: recovery.record(
                                    outcome: .recovered
                                )
                            )

                        case .applied_without_output:
                            let recoveryError =
                                AgentToolRecoveryError.applied_without_output

                            return AgentToolExecutionOutcome(
                                result: try makeToolErrorResult(
                                    for: toolCall,
                                    error: recoveryError
                                ),
                                recovery: recovery.record(
                                    outcome: .failed
                                )
                            )

                        case .not_applied:
                            recovery.advance(
                                to: state
                            )
                            continue

                        case .unknown:
                            guard decision.limit.nextAttempt(
                                after: recovery.completedAttemptsInStep
                            ) == nil else {
                                continue
                            }

                            let recoveryError =
                                AgentToolRecoveryError.reconciliation_unresolved

                            return AgentToolExecutionOutcome(
                                result: try makeToolErrorResult(
                                    for: toolCall,
                                    error: recoveryError
                                ),
                                recovery: recovery.record(
                                    outcome: .exhausted
                                )
                            )
                        }
                    } catch {
                        recovery.attempts.append(
                            Recovery.Attempt(
                                capturing: error,
                                number: permit.number,
                                action: decision.action,
                                state: recovery.state
                            )
                        )

                        guard decision.limit.nextAttempt(
                            after: recovery.completedAttemptsInStep
                        ) == nil else {
                            continue
                        }

                        return AgentToolExecutionOutcome(
                            result: try makeToolErrorResult(
                                for: toolCall,
                                error: error
                            ),
                            recovery: recovery.record(
                                outcome: .exhausted
                            )
                        )
                    }

                case .retry_same_operation:
                    if isMutationRisk(preflight.risk) {
                        do {
                            let refreshed = try await tooling.registry.preflight(
                                toolCall,
                                workspace: tooling.workspace
                            )

                            guard refreshed == preflight else {
                                let recoveryError =
                                    AgentToolRecoveryError.preflight_changed

                                recovery.attempts.append(
                                    Recovery.Attempt(
                                        capturing: recoveryError,
                                        number: permit.number,
                                        action: decision.action,
                                        state: recovery.state
                                    )
                                )

                                return AgentToolExecutionOutcome(
                                    result: try makeToolErrorResult(
                                        for: toolCall,
                                        error: recoveryError
                                    ),
                                    recovery: recovery.record(
                                        outcome: .failed
                                    )
                                )
                            }
                        } catch {
                            recovery.attempts.append(
                                Recovery.Attempt(
                                    capturing: error,
                                    number: permit.number,
                                    action: decision.action,
                                    state: recovery.state
                                )
                            )

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

                    do {
                        let result = try await tooling.registry.call(
                            toolCall,
                            workspace: tooling.workspace
                        )
                        let state = Recovery.State(
                            reconciled: isMutationRisk(preflight.risk)
                                ? .applied
                                : .none
                        )

                        recovery.state = state
                        recovery.attempts.append(
                            Recovery.Attempt(
                                number: permit.number,
                                action: decision.action,
                                status: .succeeded,
                                state: state
                            )
                        )

                        return AgentToolExecutionOutcome(
                            result: result,
                            recovery: recovery.record(
                                outcome: .recovered
                            )
                        )
                    } catch {
                        let accepted = recovery.absorb(
                            error
                        )

                        recovery.attempts.append(
                            Recovery.Attempt(
                                capturing: error,
                                number: permit.number,
                                action: decision.action,
                                state: recovery.state
                            )
                        )

                        guard accepted else {
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

                        guard AgentToolActiveRecovery.allows(
                            decision.action,
                            state: recovery.state
                        ) else {
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

                        guard decision.limit.nextAttempt(
                            after: recovery.completedAttemptsInStep
                        ) == nil else {
                            continue
                        }

                        return AgentToolExecutionOutcome(
                            result: try makeToolErrorResult(
                                for: toolCall,
                                error: error
                            ),
                            recovery: recovery.record(
                                outcome: .exhausted
                            )
                        )
                    }

                default:
                    let recoveryError =
                        AgentToolRecoveryError.action_unsupported(
                            decision.action
                        )

                    recovery.attempts.append(
                        Recovery.Attempt(
                            capturing: recoveryError,
                            number: permit.number,
                            action: decision.action,
                            state: recovery.state
                        )
                    )

                    return AgentToolExecutionOutcome(
                        result: try makeToolErrorResult(
                            for: toolCall,
                            error: recoveryError
                        ),
                        recovery: recovery.record(
                            outcome: .failed
                        )
                    )
                }
            }

            let recoveryError =
                AgentToolRecoveryError.recovery_exhausted

            return AgentToolExecutionOutcome(
                result: try makeToolErrorResult(
                    for: toolCall,
                    error: recoveryError
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
