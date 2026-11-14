import Agentic
import Foundation

extension AgentLoop {
    /// A provider batch consisting entirely of Agent calls may be launched
    /// concurrently. Checkpoint mutation remains serialized after they return.
    /// An admitted child is never run a second time on checkpoint replay.
    func processDelegatedBatch(
        from initial: AgentExecutor.Checkpoint
    ) async throws -> ToolProcessingOutcome? {
        guard delegation != nil,
              let projection = initial.lastAdvertisedCapabilities,
              let current = initial.toolBatch,
              current.records.count > 1,
              current.records.allSatisfy({ record in
                  if case .agent = projection.target(named: record.functionCall.name) {
                      return true
                  }
                  return false
              }) else {
            return nil
        }
        var checkpoint = initial
        let pendingReview = current.records.first { $0.isSuspended }
        if let pendingReview {
            return try await surfaceRetainedChild(
                pendingReview.functionCall,
                checkpoint: &checkpoint
            )
        }
        let pending = current.records.enumerated().filter { !$0.element.isTerminal }
        if pending.isEmpty {
            finishToolBatch(on: &checkpoint)
            try await saveCheckpoint(&checkpoint)
            return .continueLoop(checkpoint)
        }
        for (_, record) in pending {
            try begin_tool_invocation(
                call_id: record.functionCall.id,
                tool_name: record.functionCall.name,
                in: &checkpoint
            )
            try await recordFunctionCall(record.functionCall)
        }
        try await saveCheckpoint(&checkpoint)
        let dispatcher = await modelDispatcher(sessionID: checkpoint.id)
        let results = await withTaskGroup(
            of: (Int, DelegatedCallOutcome).self,
            returning: [(Int, DelegatedCallOutcome)].self
        ) { group in
            for (index, record) in pending {
                group.addTask {
                    let resolver = CapabilityFunctionCallResolver(
                        dispatcher: dispatcher,
                        projection: projection,
                        journal: nil
                    )
                    do {
                        return (index, .response(try await resolver.resolve(record.functionCall)))
                    } catch let suspension as RuntimeDelegatedChildSuspension {
                        return (index, .suspended(suspension))
                    } catch {
                        return (index, .error(String(describing: error)))
                    }
                }
            }
            var collected: [(Int, DelegatedCallOutcome)] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected.sorted { $0.0 < $1.0 }
        }
        var firstSuspension: RuntimeDelegatedChildSuspension?
        for (index, outcome) in results {
            let call = current.records[index].functionCall
            switch outcome {
            case .response(let result):
                try await appendToolResult(
                    result,
                    for: call,
                    disposition: result.isError ? .failed_execution : .executed,
                    to: &checkpoint,
                    summary: "delegated Agent completed"
                )
            case .error(let description):
                let response = FunctionCall.Response(
                    call: call.reference,
                    output: .object(["error": .string(description)]),
                    isError: true
                )
                try await appendToolResult(
                    response,
                    for: call,
                    disposition: .failed_execution,
                    to: &checkpoint,
                    summary: description
                )
            case .suspended(let suspension):
                if firstSuspension == nil { firstSuspension = suspension }
                markDelegatedPending(call, on: &checkpoint)
            }
            try await saveCheckpoint(&checkpoint)
        }
        if let firstSuspension {
            try await mirrorDelegatedSuspension(firstSuspension, checkpoint: &checkpoint)
            return .result(try suspendedResult(from: checkpoint))
        }
        finishToolBatch(on: &checkpoint)
        try await saveCheckpoint(&checkpoint)
        return .continueLoop(checkpoint)
    }

    enum DelegatedCallOutcome: Sendable {
        case response(FunctionCall.Response)
        case suspended(RuntimeDelegatedChildSuspension)
        case error(String)
    }

    func markDelegatedPending(
        _ call: FunctionCall,
        on checkpoint: inout AgentExecutor.Checkpoint
    ) {
        guard var batch = checkpoint.toolBatch else { return }
        batch.mark(callID: call.id, disposition: .suspended_for_delegation)
        batch.suspend()
        checkpoint.toolBatch = batch
    }

    func mirrorDelegatedSuspension(
        _ pending: RuntimeDelegatedChildSuspension,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        guard let suspension = pending.result.suspension else {
            throw AgentHistoryError.corruptedCheckpoint(
                "delegated child has no suspension payload"
            )
        }
        markDelegatedPending(pending.call, on: &checkpoint)
        var metadata = suspension.metadata
        metadata["delegated_child_session_id"] = pending.result.sessionID
        metadata["delegated_child_call_id"] = pending.call.id
        metadata["delegation_path"] =
            (metadata["delegation_path"].map { $0 + " > " } ?? "")
            + pending.result.sessionID
        checkpoint.suspend(.init(
            id: suspension.id,
            reason: suspension.reason,
            createdAt: suspension.createdAt,
            metadata: metadata
        ))
        try await saveCheckpoint(&checkpoint)
    }

    func surfaceRetainedChild(
        _ call: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> ToolProcessingOutcome {
        guard let delegation,
              let result = await delegation.latestResult(
                  "child:\(checkpoint.id.utf8.count):\(checkpoint.id):\(call.id.utf8.count):\(call.id)"
              ) else {
            throw AgentHistoryError.corruptedCheckpoint(
                "pending delegated Agent result is missing"
            )
        }
        if result.isCompleted || result.isFailed || result.isInterrupted {
            try await recordTerminalDelegatedChild(
                result,
                call: call,
                checkpoint: &checkpoint
            )
            if let next = try await processDelegatedBatch(from: checkpoint) {
                return next
            }
            return .continueLoop(checkpoint)
        }
        guard result.suspension != nil else {
            throw AgentHistoryError.corruptedCheckpoint(
                "delegated Agent is neither suspended nor terminal"
            )
        }
        try await mirrorDelegatedSuspension(
            .init(call: call, result: result),
            checkpoint: &checkpoint
        )
        return .result(try suspendedResult(from: checkpoint))
    }

    /// Called when the human stops a suspended child. No approval is
    /// fabricated: the parent receives the interrupted child's tool result.
    func resumeTerminatedDelegatedChild(
        _ checkpoint: AgentExecutor.Checkpoint
    ) async throws -> AgentExecutor.Result? {
        guard let delegation,
              let suspension = checkpoint.resolvedSuspension,
              let childID = suspension.metadata["delegated_child_session_id"],
              let callID = suspension.metadata["delegated_child_call_id"],
              let call = checkpoint.toolBatch?.record(for: callID)?.functionCall,
              let child = await delegation.latestResult(childID),
              child.isCompleted || child.isFailed || child.isInterrupted else {
            return nil
        }
        var current = checkpoint
        try await recordTerminalDelegatedChild(
            child,
            call: call,
            checkpoint: &current
        )
        return try await runLoop(from: current)
    }

    /// All resumed child outcomes use the format captured at admission.
    /// The saved model projection also binds the call to an advertised Agent.
    func delegatedAgentResponse(
        _ child: AgentExecutor.Result,
        for call: FunctionCall,
        checkpoint: AgentExecutor.Checkpoint
    ) async throws -> FunctionCall.Response {
        let expectedChildID = "child:\(checkpoint.id.utf8.count):\(checkpoint.id):\(call.id.utf8.count):\(call.id)"
        guard child.sessionID == expectedChildID,
              let projection = checkpoint.lastAdvertisedCapabilities,
              let target = projection.target(named: call.name),
              case .agent = target,
              let delegation,
              let responseFormat = await delegation.responseFormat(for: child.sessionID) else {
            throw AgentHistoryError.corruptedCheckpoint(
                "delegated child result lacks its original Agent invocation contract"
            )
        }
        return try CapabilityFunctionCallResolver.agentResponse(
            child,
            for: call,
            responseFormat: responseFormat
        ).notingStaged(by: child)
    }

    func recordTerminalDelegatedChild(
        _ child: AgentExecutor.Result,
        call: FunctionCall,
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let response = try await delegatedAgentResponse(
            child,
            for: call,
            checkpoint: checkpoint
        )
        checkpoint.clearSuspension()
        checkpoint.phase = .processing_tool_calls
        try await appendToolResult(
            response,
            for: call,
            disposition: response.isError ? .failed_execution : .executed,
            to: &checkpoint,
            summary: "delegated Agent reached terminal state"
        )
        try await saveCheckpoint(&checkpoint)
    }

    func resumeDelegatedChild(
        _ checkpoint: AgentExecutor.Checkpoint,
        interaction response: Run.Interaction.Response
    ) async throws -> AgentExecutor.Result {
        guard let delegation,
              let suspension = checkpoint.resolvedSuspension,
              let childID = suspension.metadata["delegated_child_session_id"],
              let callID = suspension.metadata["delegated_child_call_id"],
              let call = checkpoint.toolBatch?.record(for: callID)?.functionCall else {
            throw AgentHistoryError.corruptedCheckpoint(
                "delegated child interaction lacks a live pending call"
            )
        }
        let childResponse = Run.Interaction.Response(
            requestID: response.requestID,
            sessionID: childID,
            resolution: response.resolution,
            createdAt: response.createdAt,
            metadata: response.metadata
        )
        let child = try await delegation.resume(childID, interaction: childResponse)
        var current = checkpoint
        if child.suspension != nil {
            try await mirrorDelegatedSuspension(
                .init(call: call, result: child),
                checkpoint: &current
            )
            return try suspendedResult(from: current)
        }
        try await recordTerminalDelegatedChild(
            child,
            call: call,
            checkpoint: &current
        )
        return try await runLoop(from: current)
    }

    /// The provider may execute semantic callbacks before its assistant turn
    /// has completed. Rebuild an explicit tool-use checkpoint before returning
    /// the child's pending review to the Host.
    func suspendNativeDelegatedChild(
        _ pending: RuntimeDelegatedChildSuspension,
        invocations: [ToolInvocation.Result],
        semanticInvocations: [ModelSemanticInvocationResult],
        checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        checkpoint.state.iteration += 1
        try await applyNativeToolInvocations(invocations, to: &checkpoint)
        try await applyNativeSemanticInvocations(semanticInvocations, to: &checkpoint)
        let response = AgentResponse(
            message: Message(
                role: .assistant,
                content: MessageContent(blocks: [.call(pending.call)])
            ),
            stopReason: .tool_use
        )
        checkpoint.state.messages.append(response.message)
        checkpoint.lastResponse = response
        checkpoint.partialResponse = nil
        storeToolBatch(AgentToolUseBatch(response: response), to: &checkpoint)
        try await recordMessage(response.message)
        try await recordFunctionCall(pending.call)
        try await mirrorDelegatedSuspension(pending, checkpoint: &checkpoint)
    }
}

public extension FunctionCall.Response {
    /// A worker's changes that are staged but not yet published read as
    /// such to the delegator, so it neither retries them nor looks for them
    /// on disk. Tools report staging through their projection's status.
    func notingStaged(
        by child: AgentExecutor.Result
    ) -> FunctionCall.Response {
        let staged = child.toolUses
            .compactMap { $0.result?.projection }
            .filter { $0.status == "staged" }
        guard !staged.isEmpty else {
            return self
        }
        let changes = staged.flatMap { projection in
            projection.facts.isEmpty
                ? [projection.summary ?? "changes"]
                : projection.facts.map { "\($0.label) (\($0.value))" }
        }
        return rendered(
            modelText
                + "\n[Staged by the worker, not yet on disk: \(changes.joined(separator: ", ")). "
                + "This is the expected outcome: the operator publishes staged changes after the run, "
                + "so the files on disk still show the old content until then. Reading them now cannot "
                + "confirm or refute the change; the staged diff is the record. Do not re-read the "
                + "files, retry, or redo these changes; report them as staged and continue.]"
        )
    }
}
