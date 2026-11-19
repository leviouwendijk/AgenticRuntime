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
    /// puts what an earlier run of the conversation revealed last, as that
    /// run's requests had it. This keeps the order stable; it does not keep
    /// the cache: the tools come before the system prompt and the history,
    /// so any change to them, appended or not, rewrites the whole prefix.
    func advertisingOrder(
        _ projection: ModelCapabilityProjection,
        after previous: Run.Event.Advertisement?
    ) -> ModelCapabilityProjection {
        if let previous {
            return projection.ordered(by: previous.entries.map(\.name))
        }
        let carried = configuration.carried.references.map(\.identifier)
        let names = projection.functions.map(\.name)
        return projection.ordered(by: names.filter { !carried.contains($0) } + carried)
    }

    /// Reports the advertised schemas when they differ from the last report,
    /// in name, order or form, with what each costs as sent and in full.
    func recordAdvertisement(
        _ tools: [ToolDescriptor],
        full: [ToolDescriptor],
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
           previous.entries.map(\.detail) == shape.map(\.1) {
            return
        }

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
            rewritesCachedPrefix: previous != nil
        )
        let core = entries.filter { $0.detail == .core }.count
        var summary = "\(entries.count) schema\(entries.count == 1 ? "" : "s"), ≈\(advertisement.estimatedTokens) tokens"
        if core > 0 {
            summary += " (\(core) core; ≈\(advertisement.fullTokens) in full)"
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
