import Agentic
import Foundation
import Tokens

public enum ContextAllocatorError: Error, Equatable {
    case invalidPolicy
    case duplicateWorkingSet(String)
    case unknownWorkingSet(String)
    case invalidAllocation(String)
    case unknownAllocation(String)
    case invalidPreferredBudget(Int)
    case concurrentPreparation(String)
    case workingSetChanged(String)
    case invalidResolution(String)
    case requiredEvidenceExceedsBudget(String)
    case requiredEvidenceExceedsResolutionLimit(String)
    case unavailableAgent(AgentIdentifier)
    case unavailableProgram(ProgramIdentifier)
    case unknownPreset(String)
}

public extension Context {
    /// Deterministic allocation and preparation. No model calls, recursive
    /// inference or arbitrary source access occur inside this actor.
    actor Allocator {
        public let policy: Policy
        private var workingSets: [String: WorkingSet] = [:]
        private var versions: [String: Int] = [:]
        private var preparing: Set<String> = []
        private var transitions: [Transition] = []
        private var rolePresets: [String: Snapshot] = [:]

        public init(policy: Policy = .init()) throws {
            guard policy.preferredInputTokens > 0,
                  policy.maximumInputTokens >= policy.preferredInputTokens,
                  policy.reservedOutputTokens >= 0,
                  policy.maximumResolutions > 0,
                  policy.history.maximumTurns > 0,
                  policy.history.maximumTokens > 0
            else {
                throw ContextAllocatorError.invalidPolicy
            }
            self.policy = policy
        }

        public func createWorkingSet(
            id: String,
            inheriting parentID: String? = nil
        ) throws {
            guard !id.isEmpty, workingSets[id] == nil else {
                throw ContextAllocatorError.duplicateWorkingSet(id)
            }
            let parent: WorkingSet?
            if let parentID {
                guard let existing = workingSets[parentID] else {
                    throw ContextAllocatorError.unknownWorkingSet(parentID)
                }
                parent = existing
            } else {
                parent = nil
            }
            workingSets[id] = WorkingSet(
                id: id,
                parentID: parentID,
                allocations: parent?.allocations ?? [],
                preferredInputTokens: parent?.preferredInputTokens
            )
            versions[id] = 0
        }

        public func snapshot(_ id: String) throws -> WorkingSet {
            guard let current = workingSets[id] else {
                throw ContextAllocatorError.unknownWorkingSet(id)
            }
            return current
        }

        public func recordedOperations(for id: String) -> [Transition] {
            transitions.filter { $0.workingSetID == id }
        }

        /// Atomically replace a preset of already-resolved optional collaborators.
        /// No models run here, and no capability authority is granted.
        /// In-flight callers retain their immutable previous snapshot.
        public func configure(_ preset: Preset) {
            let revision = (rolePresets[preset.id]?.revision ?? 0) + 1
            rolePresets[preset.id] = Snapshot(revision: revision, preset: preset)
        }

        /// This is separate from snapshot(_:) for working sets.
        public func preset(_ id: String) throws -> Snapshot {
            guard let snapshot = rolePresets[id] else {
                throw ContextAllocatorError.unknownPreset(id)
            }
            return snapshot
        }

        /// Transactional: all operations validate before any state is replaced.
        public func apply(
            _ operations: [Operation],
            to id: String
        ) throws {
            guard var next = workingSets[id] else {
                throw ContextAllocatorError.unknownWorkingSet(id)
            }
            for operation in operations {
                switch operation {
                case .allocate(let item):
                    guard !item.id.isEmpty, !item.pointer.source.isEmpty,
                          !item.pointer.record.isEmpty,
                          item.dependencies.allSatisfy({ !$0.source.isEmpty && !$0.record.isEmpty })
                    else {
                        throw ContextAllocatorError.invalidAllocation(item.id)
                    }
                    var normalized = item
                    normalized.state = .active
                    if let position = next.allocations.firstIndex(where: { $0.id == item.id }) {
                        next.allocations[position] = normalized
                    } else {
                        next.allocations.append(normalized)
                    }
                case .release(let allocationID), .invalidate(let allocationID):
                    guard let position = next.allocations.firstIndex(where: { $0.id == allocationID }) else {
                        throw ContextAllocatorError.unknownAllocation(allocationID)
                    }
                    if case .release = operation {
                        next.allocations[position].state = .released
                    } else {
                        next.allocations[position].state = .invalidated
                    }
                case .setPreferredInputTokens(let value):
                    guard value > 0, value <= policy.maximumInputTokens else {
                        throw ContextAllocatorError.invalidPreferredBudget(value)
                    }
                    next.preferredInputTokens = value
                }
            }
            workingSets[id] = next
            versions[id, default: 0] += 1
            for operation in operations {
                transitions.append(.init(sequence: transitions.count + 1, workingSetID: id, operation: operation))
            }
        }

        /// Resolver enforces per-source/session authorization. Each resolved
        /// group remains intact; optional groups can be omitted, required groups
        /// cannot be silently omitted or truncated. Token counts are estimates.
        public func prepareFrame(
            for id: String,
            using resolver: any RecordResolving,
            modelContextLimit: Int
        ) async throws -> Frame {
            guard let current = workingSets[id] else {
                throw ContextAllocatorError.unknownWorkingSet(id)
            }
            guard !preparing.contains(id) else {
                throw ContextAllocatorError.concurrentPreparation(id)
            }
            preparing.insert(id)
            defer { preparing.remove(id) }

            let startingVersion = versions[id, default: 0]
            let hardLimit = max(0, min(policy.maximumInputTokens,
                modelContextLimit - policy.reservedOutputTokens))
            let preferred = current.preferredInputTokens ?? policy.preferredInputTokens
            let inputBudget = min(preferred, hardLimit)
            let ordered = current.allocations.enumerated()
                .filter { $0.element.state == .active }
                .sorted { lhs, rhs in
                    if lhs.element.required != rhs.element.required {
                        return lhs.element.required
                    }
                    if lhs.element.priority != rhs.element.priority {
                        return lhs.element.priority > rhs.element.priority
                    }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)

            var items: [Frame.Item] = []
            var skipped: [String] = []
            var used = 0
            var resolutions = 0
            let encoder = JSONEncoder()
            for allocation in ordered {
                guard resolutions < policy.maximumResolutions else {
                    if allocation.required {
                        throw ContextAllocatorError.requiredEvidenceExceedsResolutionLimit(allocation.id)
                    }
                    skipped.append(allocation.id)
                    continue
                }
                resolutions += 1
                let observation = try await resolver.resolve(allocation.pointer)
                guard observation.pointer.source == allocation.pointer.source,
                      observation.pointer.record == allocation.pointer.record,
                      observation.pointer.selection == allocation.pointer.selection,
                      case .recorded = observation.pointer.revision
                else {
                    throw ContextAllocatorError.invalidResolution(allocation.id)
                }
                if case .recorded(let expected) = allocation.pointer.revision,
                   observation.pointer.revision != .recorded(expected) {
                    throw ContextAllocatorError.invalidResolution(allocation.id)
                }
                let encoded = try encoder.encode(observation.messages)
                let estimated = max(1, TokenEstimator.estimate(
                    String(decoding: encoded, as: UTF8.self),
                    options: .agenticContext,
                    source: "context.allocated_messages_json"
                ).estimatedTokens)
                if estimated > inputBudget - used {
                    if allocation.required {
                        throw ContextAllocatorError.requiredEvidenceExceedsBudget(allocation.id)
                    }
                    skipped.append(allocation.id)
                    continue
                }
                items.append(.init(
                    allocationID: allocation.id,
                    observed: observation.pointer,
                    messages: observation.messages,
                    estimatedTokens: estimated
                ))
                used += estimated
            }
            guard versions[id] == startingVersion else {
                throw ContextAllocatorError.workingSetChanged(id)
            }
            return Frame(
                workingSetID: id,
                items: items,
                skippedAllocationIDs: skipped,
                inputBudget: inputBudget,
                estimatedInputTokens: used
            )
        }
    }
}
