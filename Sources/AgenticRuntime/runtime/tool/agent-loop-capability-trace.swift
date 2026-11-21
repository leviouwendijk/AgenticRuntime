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
            changes += initial.visible.references.map {
                .init(reference: $0, operation: .exposed, source: .declared)
            }
            baseline = initial
        }

        func source(_ reference: CapabilityReference, _ operation: Run.Event.CapabilityChange.Operation) -> Run.Event.CapabilityChange.Source {
            if let grant = granted.first(where: { $0.1.references.contains(reference) })?.0 {
                return .init(grant)
            }
            return .other
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

    /// The capabilities this request declares to the provider, in order.
    /// The tool definitions come first in the provider's cached prefix, so
    /// they stay as the conversation fixed them: as an earlier run declared
    /// them (`Configuration.declared`), else as this run's first request
    /// did. Every other available capability is callable without one. What
    /// the visible set adds or drops since is pending; a refresh (a
    /// compaction in this run, or the host passing nil) declares the
    /// visible set, applying it.
    func declaring(
        refresh: Bool,
        in checkpoint: inout AgentExecutor.Checkpoint
    ) async throws -> (
        declared: [CapabilityReference],
        pending: Run.Event.Advertisement.Pending,
        refreshed: Bool
    ) {
        let visible = try await inventory.visibleDeclarations()
        let current = checkpoint.declared ?? configuration.declared
        var declared = current ?? visible
        var refreshed = false
        if refresh, let current, current != visible {
            declared = visible
            refreshed = true
        }
        // A capability the session declared earlier may be gone: renamed
        // (`read` became `io_tool_read`) or uninstalled since. Its definition
        // can't be sent again, and the cached prefix no longer matches, so the
        // session declares what is visible now.
        if !refreshed, let current {
            let installed = Set(await capabilityState.snapshot().installed.references)
            if current.contains(where: { !installed.contains($0) }) {
                declared = visible
                refreshed = true
            }
        }
        checkpoint.declared = declared
        let pending = Run.Event.Advertisement.Pending(
            added: visible.filter { !declared.contains($0) }.map(\.identifier),
            removed: declared.filter { !visible.contains($0) }.map(\.identifier)
        )
        return (declared, pending, refreshed)
    }

    /// Reports the advertised schemas when they differ from the last report,
    /// in name, order or form, or in what is callable or pending, with what
    /// each costs as sent and in full.
    func recordAdvertisement(
        _ tools: [ToolDescriptor],
        full: [ToolDescriptor],
        projection: ModelCapabilityProjection,
        pending: Run.Event.Advertisement.Pending,
        refreshed: Bool,
        detail: ContextWindow.SchemaDetail,
        reason: Run.Event.Advertisement.Reason,
        to checkpoint: inout AgentExecutor.Checkpoint
    ) async throws {
        let shape = zip(tools, full).map { sent, full in
            (sent.name, sent == full ? ContextWindow.SchemaDetail.full : .core)
        }
        let previous = checkpoint.events.last { $0.kind == .schemas_advertised }?.advertisement
        let pendingRecord = pending.isEmpty ? nil : pending
        if let previous,
           previous.entries.map(\.name) == shape.map(\.0),
           previous.entries.map(\.detail) == shape.map(\.1),
           previous.callable == projection.callable.count,
           previous.pending == pendingRecord,
           !refreshed {
            return
        }
        // Only a change to what is declared rewrites the cached prefix.
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
                reference: projection.target(named: shape.0),
                detail: shape.1,
                estimatedTokens: tokens(pair.0),
                fullTokens: shape.1 == .full ? tokens(pair.0) : tokens(pair.1)
            )
        }
        let advertisement = Run.Event.Advertisement(
            detail: detail,
            reason: reason,
            entries: entries,
            callable: projection.callable.count,
            pending: pendingRecord,
            refreshed: refreshed,
            rewritesCachedPrefix: declaredChanged
        )
        let core = entries.filter { $0.detail == .core }.count
        var summary = "\(entries.count) schema\(entries.count == 1 ? "" : "s"), ≈\(advertisement.estimatedTokens) tokens"
        if core > 0 {
            summary += " (\(core) core; ≈\(advertisement.fullTokens) in full)"
        }
        if advertisement.callable > 0 {
            summary += " · \(advertisement.callable) more callable"
        }
        if let pendingRecord {
            let changes = pendingRecord.added.map { "+" + $0 } + pendingRecord.removed.map { "−" + $0 }
            summary += " · pending until refresh: " + changes.joined(separator: ", ")
        }
        if refreshed {
            summary += " · definitions refreshed"
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
