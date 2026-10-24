import Difference

public enum AgentExecutionTraceDifferenceError: Error, Sendable, Equatable {
    case different_roots
}

public extension AgentExecutionTrace {
    /// Compare two observations of the same run/program, preserving occurrence IDs.
    /// This is snapshot evolution, not a comparison of unrelated sessions.
    func difference(from before: AgentExecutionTrace) throws -> TreeDifference<AgentExecutionTraceNode> {
        guard id == before.id else {
            throw AgentExecutionTraceDifferenceError.different_roots
        }
        return try TreeDiffer.make(
            before: before.tree,
            after: tree,
            identity: \.id,
            label: \.title,
            equivalent: ==
        )
    }

    func difference_layout(from before: AgentExecutionTrace) throws -> TreeDifferenceLayout {
        .make(try difference(from: before))
    }
}
