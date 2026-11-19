import Agentic
import AgenticStandard
import Foundation
import Tokens

extension AgentLoop {
    /// Reports how the capabilities differ from the last report: on the
    /// first request the opening (declared view and each grant; authority
    /// only counted), afterwards every change in authority or view, each
    /// with its source.
    func recordCapabilityChanges(
        before initial: AgentCapabilityState.Snapshot,
        granted: [(AgentCapabilityGrant, AgentCapabilitySet)],
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let after = await capabilityState.snapshot()
        defer { checkpoint.reportedCapabilities = after }
        var changes: [Run.Event.CapabilityChange] = []
        let baseline: AgentCapabilityState.Snapshot
        if let reported = checkpoint.reportedCapabilities {
            baseline = reported
        } else {
            let carried = configuration.carried.references
            changes += initial.visible.references.map {
                .init(reference: $0, operation: .exposed, source: carried.contains($0) ? .carried : .declared)
            }
            baseline = initial
        }

        func source(_ reference: CapabilityReference, _ operation: Run.Event.CapabilityChange.Operation) -> Run.Event.CapabilityChange.Source {
            if let grant = granted.first(where: { $0.1.references.contains(reference) })?.0 {
                return .init(grant)
            }
            return operation == .exposed ? .tool_reveal : .other
        }
        func diff(
            _ from: AgentCapabilitySet,
            _ to: AgentCapabilitySet,
            added: Run.Event.CapabilityChange.Operation,
            removed: Run.Event.CapabilityChange.Operation
        ) {
            for reference in to.subtracting(from).references {
                changes.append(.init(reference: reference, operation: added, source: source(reference, added)))
            }
            for reference in from.subtracting(to).references {
                changes.append(.init(reference: reference, operation: removed, source: source(reference, removed)))
            }
        }
        diff(baseline.available, after.available, added: .enabled, removed: .disabled)
        diff(baseline.visible, after.visible, added: .exposed, removed: .hidden)
        guard !changes.isEmpty else { return }

        var summary = Dictionary(grouping: changes) { "\($0.operation.rawValue) by \($0.source.rawValue)" }
            .map { "\($1.count) \($0)" }
            .sorted()
        if checkpoint.reportedCapabilities == nil {
            summary.append("\(after.available.references.count) available")
        }
        try await appendRunEvent(
            .init(
                kind: .capability_changed,
                iteration: checkpoint.state.iteration,
                summary: summary.joined(separator: ", "),
                capabilityChanges: changes
            ),
            to: &checkpoint
        )
    }

    /// The order to advertise in, so the tools only grow at the end: the
    /// previous request's order, then anything new. A run's first request
    /// takes the order an earlier run of the conversation declared in, or
    /// without one puts what that run revealed last. This keeps the order
    /// stable; it does not keep the cache: the tools come before the system
    /// prompt and the history, so any change to them, appended or not,
    /// rewrites the whole prefix.
    func advertisingOrder(
        _ projection: ModelCapabilityProjection,
        after previous: Run.Event.Advertisement?
    ) -> ModelCapabilityProjection {
        if let previous {
            return projection.ordered(by: previous.entries.map(\.name))
        }
        if let declared = configuration.declaredFunctions {
            return projection.ordered(by: declared)
        }
        let carried = configuration.carried.references.map(\.identifier)
        let names = projection.functions.map(\.name)
        return projection.ordered(by: names.filter { !carried.contains($0) } + carried)
    }

    /// Fixes the run's tool definitions at its first request, and decides
    /// for each capability that becomes visible later how it reaches the
    /// model. The provider's cached prefix is tools, then system, then
    /// history, so declaring it rewrites the whole prompt once; deferring it
    /// to `call_capability` keeps the prompt cached, at the cost of an
    /// indirection and no provider-side schema for its input. Declared while
    /// the request is at most `contextPolicy.deferRevealsAbove` estimated
    /// tokens, deferred above; a deferred capability stays deferred. What an
    /// earlier run of the conversation revealed keeps the form that run gave
    /// it (`Configuration.declaredFunctions`), so the definitions open as it
    /// left them; without that record it is decided the same way at this
    /// run's first request.
    func declaring(
        _ projection: ModelCapabilityProjection,
        in checkpoint: inout AgentExecutor.Checkpoint
    ) -> (projection: ModelCapabilityProjection, decision: Run.Event.Advertisement.RevealDecision?) {
        let names = projection.entries.map(\.function.name)
        let dispatcher = Standard.Tools.CallCapability.identifier.rawValue
        let previous = checkpoint.events.last { $0.kind == .schemas_advertised }?.advertisement
        var declared: [String]
        let pending: [String]
        if let fixed = checkpoint.declaredFunctions {
            declared = fixed
            let deferred = previous?.deferred ?? []
            pending = names.filter { !fixed.contains($0) && !deferred.contains($0) }
        } else {
            let carried = configuration.carried.references.map(\.identifier)
            let isCarried = { (name: String) in
                carried.contains(projection.target(named: name)?.identifier ?? name)
            }
            if let earlier = configuration.declaredFunctions {
                declared = names.filter { !isCarried($0) || earlier.contains($0) }
                // Without the dispatcher declared there is no other way in.
                if !declared.contains(dispatcher) {
                    declared = names
                }
                pending = []
            } else {
                declared = names.filter { !isCarried($0) }
                pending = names.filter(isCarried)
            }
        }

        var decision: Run.Event.Advertisement.RevealDecision?
        if !pending.isEmpty {
            let threshold = configuration.contextPolicy.deferRevealsAbove
            let prompt = AgentRequest(messages: checkpoint.state.messages)
                .estimatedInputTokens().estimatedTokens
                + (previous?.estimatedTokens ?? 0)
            // Without the dispatcher declared there is no other way in.
            let limit = declared.contains(dispatcher) ? threshold : nil
            let throughDispatcher = limit.map { prompt > $0 } == true
            if !throughDispatcher {
                declared += pending
            }
            decision = .init(
                capabilities: pending,
                deferred: throughDispatcher,
                estimatedPromptTokens: prompt,
                threshold: limit
            )
        }
        checkpoint.declaredFunctions = declared
        return (projection.deferring(names.filter { !declared.contains($0) }), decision)
    }

    /// Reports the advertised schemas when they differ from the last report,
    /// in name, order or form, with what each costs as sent and in full.
    func recordAdvertisement(
        _ tools: [ToolDescriptor],
        full: [ToolDescriptor],
        deferred: [String],
        revealDecision: Run.Event.Advertisement.RevealDecision?,
        detail: ContextWindow.SchemaDetail,
        reason: Run.Event.Advertisement.Reason,
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let shape = zip(tools, full).map { sent, full in
            (sent.name, sent == full ? ContextWindow.SchemaDetail.full : .core)
        }
        let previous = checkpoint.events.last { $0.kind == .schemas_advertised }?.advertisement
        if let previous,
           previous.entries.map(\.name) == shape.map(\.0),
           previous.entries.map(\.detail) == shape.map(\.1),
           previous.deferred == deferred {
            return
        }
        // Only a change to what is declared rewrites the cached prefix; a
        // deferred reveal adds to the history.
        let declaredChanged = previous.map {
            $0.entries.map(\.name) != shape.map(\.0) || $0.entries.map(\.detail) != shape.map(\.1)
        } ?? false

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func tokens(_ descriptor: ToolDescriptor) -> Int {
            guard let data = try? encoder.encode(descriptor) else { return 0 }
            return TokenEstimator.estimate(
                String(decoding: data, as: UTF8.self),
                options: .agenticContext
            ).estimatedTokens
        }
        let entries = zip(zip(tools, full), shape).map { pair, shape in
            Run.Event.Advertisement.Entry(
                name: shape.0,
                detail: shape.1,
                estimatedTokens: tokens(pair.0),
                fullTokens: shape.1 == .full ? tokens(pair.0) : tokens(pair.1)
            )
        }
        let advertisement = Run.Event.Advertisement(
            detail: detail,
            reason: reason,
            entries: entries,
            deferred: deferred,
            revealDecision: revealDecision,
            rewritesCachedPrefix: declaredChanged
        )
        let core = entries.filter { $0.detail == .core }.count
        var summary = "\(entries.count) schema\(entries.count == 1 ? "" : "s"), ≈\(advertisement.estimatedTokens) tokens"
        if core > 0 {
            summary += " (\(core) core; ≈\(advertisement.fullTokens) in full)"
        }
        if !deferred.isEmpty {
            summary += " · \(deferred.count) through call_capability"
        }
        if let revealDecision {
            let limit = revealDecision.threshold.map { "\($0)" } ?? "no limit"
            summary += revealDecision.deferred
                ? " · deferred \(revealDecision.capabilities.joined(separator: ", ")): prompt ≈\(revealDecision.estimatedPromptTokens) > \(limit)"
                : " · declared \(revealDecision.capabilities.joined(separator: ", ")): prompt ≈\(revealDecision.estimatedPromptTokens) ≤ \(limit)"
        }
        summary += " · \(reason.rawValue)"
        if advertisement.rewritesCachedPrefix {
            summary += " · tools changed: the cached prefix is written again"
        }
        try await appendRunEvent(
            .init(
                kind: .schemas_advertised,
                iteration: checkpoint.state.iteration,
                summary: summary,
                advertisement: advertisement
            ),
            to: &checkpoint
        )
    }
}

extension AgentCapabilitySet {
    var references: [CapabilityReference] {
        tools.map(CapabilityReference.tool)
            + programs.map(CapabilityReference.program)
            + inferences.map(CapabilityReference.inference)
            + agents.map(CapabilityReference.agent)
    }
}
