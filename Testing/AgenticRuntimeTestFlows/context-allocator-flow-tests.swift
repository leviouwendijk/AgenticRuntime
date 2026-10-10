import Agentic
import AgenticRuntime
import Foundation
import TestFlows

private struct ContextFixtureResolver: Context.RecordResolving {
    let content: [String: String]

    func resolve(_ pointer: Context.Pointer) async throws -> Context.Resolved {
        guard let text = content[pointer.record] else {
            throw ContextAllocatorError.invalidResolution(pointer.record)
        }
        let observed = Context.Pointer(
            source: pointer.source,
            record: pointer.record,
            selection: pointer.selection,
            revision: .recorded("fixture-v1")
        )
        return .init(pointer: observed, messages: [.init(role: .user, text: text)])
    }
}

private struct ReenteringContextResolver: Context.RecordResolving {
    let allocator: Context.Allocator

    func resolve(_ pointer: Context.Pointer) async throws -> Context.Resolved {
        _ = try await allocator.prepareFrame(
            for: "recursion", using: self, modelContextLimit: 1_500
        )
        return .init(pointer: pointer, messages: [])
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runContextAllocator() async throws -> [TestDiagnostic] {
        let allocator = try Context.Allocator(policy: .init(
            preferredInputTokens: 400,
            maximumInputTokens: 1_200,
            reservedOutputTokens: 50,
            maximumResolutions: 4
        ))
        let a = Context.Allocation(
            id: "goal", pointer: .init(source: "session-A", record: "goal"),
            priority: 10, required: true
        )
        let b = Context.Allocation(
            id: "failure", pointer: .init(source: "session-B", record: "failed-run"),
            representation: .facts
        )
        let c = Context.Allocation(
            id: "source", pointer: .init(source: "repository", record: "large-source"),
            priority: -10
        )
        try await allocator.createWorkingSet(id: "primary")
        try await allocator.apply([.allocate(a), .allocate(b), .allocate(c)], to: "primary")
        try await allocator.createWorkingSet(id: "child", inheriting: "primary")
        try await allocator.apply([.release("failure")], to: "child")
        let resolver = ContextFixtureResolver(content: [
            "goal": "Complete the feature.",
            "failed-run": "Previously failed due to a stale patch.",
            "large-source": String(repeating: "source-code-", count: 150),
        ])
        let parent = try await allocator.prepareFrame(for: "primary", using: resolver, modelContextLimit: 1_500)
        let child = try await allocator.prepareFrame(for: "child", using: resolver, modelContextLimit: 1_500)
        try Expect.equal(parent.items.map(\.allocationID), ["goal", "failure"], "Budget skips optional source content without dropping required goal")
        try Expect.equal(child.items.map(\.allocationID), ["goal"], "Child release does not remove parent evidence")
        try Expect.equal(try await allocator.snapshot("primary").allocations.first(where: { $0.id == "failure" })?.state, .active, "Parent working set remains unchanged")
        try Expect.equal(parent.items[0].observed.revision, .recorded("fixture-v1"), "Frame records observed revision")

        var rollback = false
        do {
            try await allocator.apply([.release("goal"), .release("absent")], to: "primary")
        } catch ContextAllocatorError.unknownAllocation {
            rollback = true
        }
        try Expect.equal(rollback, true, "Invalid multi-operation update is rejected")
        try Expect.equal(try await allocator.snapshot("primary").allocations.first(where: { $0.id == "goal" })?.state, .active, "Failed operation leaves all allocations unchanged")

        try await allocator.apply([.invalidate("failure"), .setPreferredInputTokens(800)], to: "primary")
        let changed = try await allocator.prepareFrame(for: "primary", using: resolver, modelContextLimit: 220)
        try Expect.equal(changed.inputBudget, 170, "Model context capacity bounds preferred allocation budget")
        try Expect.equal(changed.items.map(\.allocationID), ["goal"], "Invalidated facts are not included in frames")
        try Expect.equal(try await allocator.snapshot("primary").allocations.first(where: { $0.id == "failure" })?.state, .invalidated, "Invalidation preserves the original allocation record")
        try Expect.equal(await allocator.recordedOperations(for: "primary").count, 5, "Successful allocation operations remain inspectable")

        try await allocator.createWorkingSet(id: "recursion")
        try await allocator.apply([.allocate(a)], to: "recursion")
        var recursionRejected = false
        do {
            _ = try await allocator.prepareFrame(
                for: "recursion",
                using: ReenteringContextResolver(allocator: allocator),
                modelContextLimit: 1_500
            )
        } catch ContextAllocatorError.concurrentPreparation {
            recursionRejected = true
        }
        try Expect.equal(recursionRejected, true, "Resolver cannot recursively prepare the same working set")

        try await allocator.createWorkingSet(id: "pinned")
        try await allocator.apply([
            .allocate(.init(
                id: "pinned",
                pointer: .init(source: "session-A", record: "goal", revision: .recorded("older")),
                required: true
            ))
        ], to: "pinned")
        var staleRejected = false
        do {
            _ = try await allocator.prepareFrame(for: "pinned", using: resolver, modelContextLimit: 1_500)
        } catch ContextAllocatorError.invalidResolution {
            staleRejected = true
        }
        try Expect.equal(staleRejected, true, "Pinned evidence refuses a different observed revision")

        return [
            .message("Context allocator proves cross-source input, child isolation, bounded frames, invalidation and atomic updates"),
            .field("parent_items", String(parent.items.count)),
            .field("child_items", String(child.items.count)),
        ]
    }
}
