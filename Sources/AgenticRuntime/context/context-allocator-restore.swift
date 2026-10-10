import Agentic

public enum ContextRestorationError: Error, Sendable, Equatable {
    case inheritedWorkingSetRequiresParent(String)
    case sequenceMismatch(Int)
    case mismatchedWorkingSet
}

public extension Context.Allocator {
    /// Restore from the recorded operations; refuse altered or partial state.
    /// Dynamic sessions in D1 create root working sets, not inherited sets.
    func restore(
        _ saved: Context.WorkingSet,
        transitions: [Context.Transition]
    ) throws {
        if let parentID = saved.parentID {
            throw ContextRestorationError.inheritedWorkingSetRequiresParent(parentID)
        }
        try createWorkingSet(id: saved.id)
        for (offset, transition) in transitions.enumerated() {
            guard transition.workingSetID == saved.id,
                  transition.sequence == offset + 1 else {
                throw ContextRestorationError.sequenceMismatch(offset + 1)
            }
            try apply([transition.operation], to: saved.id)
        }
        guard try snapshot(saved.id) == saved else {
            throw ContextRestorationError.mismatchedWorkingSet
        }
    }
}
