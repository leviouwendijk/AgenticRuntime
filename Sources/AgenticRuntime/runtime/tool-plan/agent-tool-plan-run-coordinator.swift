import Agentic
import AgenticExecution
import Foundation

public enum AgentToolPlanRunCoordinatorError:
    Error,
    Sendable,
    LocalizedError,
    Equatable
{
    case duplicateRunID(String)
    case missingRun(String)
    case runBusy(String)
    case staleRevision(
        runID: String,
        expected: Int,
        actual: Int
    )
    case recoveryParentNotSuspended(String)
    case recoveryParentAlreadyResolved(String)
    case activeRecoveryChild(parentRunID: String, childRunID: String)
    case maximumRecoveryDepthExceeded(parentRunID: String, maximumDepth: Int)

    public var errorDescription: String? {
        switch self {
        case .duplicateRunID(let runID):
            return "AgentToolPlanRun '\(runID)' already exists in this runtime coordinator."

        case .missingRun(let runID):
            return "No live AgentToolPlanRun exists for id '\(runID)'."

        case .runBusy(let runID):
            return "AgentToolPlanRun '\(runID)' already has an execution control in flight."

        case .staleRevision(
            let runID,
            let expected,
            let actual
        ):
            return "AgentToolPlanRun '\(runID)' revision is \(actual), not expected revision \(expected)."

        case .recoveryParentNotSuspended(let runID):
            return "AgentToolPlanRun '\(runID)' is not suspended at a recoverable failure."

        case .recoveryParentAlreadyResolved(let runID):
            return "AgentToolPlanRun '\(runID)' has already resolved its interruption and is awaiting continuation."

        case .activeRecoveryChild(let parentRunID, let childRunID):
            return "AgentToolPlanRun '\(parentRunID)' has active recovery child '\(childRunID)' for its current suspension."

        case .maximumRecoveryDepthExceeded(let parentRunID, let maximumDepth):
            return "AgentToolPlanRun '\(parentRunID)' cannot create another recovery because the maximum recovery depth is \(maximumDepth)."
        }
    }
}

/// Process-local owner for live resumable tool-plan runs.
///
/// This deliberately has no persistence contract. A longer-lived Runtime host
/// may retain one coordinator for as long as its interactive/session process is
/// alive. Durable restoration can be designed later without changing the
/// execution semantics represented by AgentToolPlanRun.
public actor AgentToolPlanRunCoordinator {
    public let executor: AgentToolPlanRunExecutor
    public let context: AgentToolExecutionContext
    public let approvalHandler: (any ToolApprovalHandler)?
    public let maximumRecoveryDepth: Int

    private var runsByID: [String: AgentToolPlanRun] = [:]
    private var runOrder: [String] = []
    private var busyRunIDs: Set<String> = []
    private var recoveryParentRevisionsByRunID: [String: Int] = [:]
    private var executionPoliciesByRunID: [String: AgentToolPlanExecutionPolicy] = [:]
    private var pauseEligibleRunIDs: Set<String> = []
    private var pauseRequestedRunIDs: Set<String> = []

    public init(
        invoker: ToolInvoker,
        context: AgentToolExecutionContext = .init(),
        approvalHandler: (any ToolApprovalHandler)? = nil,
        maximumRecoveryDepth: Int = 4
    ) {
        self.executor = AgentToolPlanRunExecutor(
            invoker: invoker
        )
        self.context = context
        self.approvalHandler = approvalHandler
        self.maximumRecoveryDepth = max(0, maximumRecoveryDepth)
    }

    public func start(
        _ plan: AgentToolPlan,
        runID: String = UUID().uuidString
    ) async throws -> AgentToolPlanRun {
        try reserveNewRun(
            runID
        )
        defer {
            busyRunIDs.remove(
                runID
            )
        }

        let run = try await executor.start(
            plan,
            runID: runID,
            relationship: .root,
            context: context,
            approvalHandler: approvalHandler
        )

        storeNew(
            run
        )

        return run
    }

    /// Execute a serial ToolPlan under an explicit run execution policy.
    ///
    /// This lane deliberately uses AgenticExecution's authored-call stepping
    /// semantics so Runtime can observe safe boundaries between calls. The
    /// existing start(_:runID:) remains the general ToolPlan path for plans
    /// whose batch or outcome-branch structure is not single-step capable yet.
    public func start(
        _ plan: AgentToolPlan,
        runID: String = UUID().uuidString,
        executionPolicy: AgentToolPlanExecutionPolicy
    ) async throws -> AgentToolPlanRun {
        try reserveNewRun(
            runID
        )
        executionPoliciesByRunID[runID] = executionPolicy

        if executionPolicy == .continuous {
            pauseEligibleRunIDs.insert(
                runID
            )
        }

        var retainExecutionPolicy = false

        defer {
            busyRunIDs.remove(
                runID
            )

            if !retainExecutionPolicy {
                executionPoliciesByRunID.removeValue(
                    forKey: runID
                )
            }

            pauseEligibleRunIDs.remove(
                runID
            )
            pauseRequestedRunIDs.remove(
                runID
            )
        }

        let started = try await executor.start(
            plan,
            runID: runID,
            relationship: .root,
            executionPolicy: .single_step,
            context: context,
            approvalHandler: approvalHandler
        )

        storeNew(
            started
        )
        retainExecutionPolicy = true

        switch executionPolicy {
        case .single_step:
            return started

        case .continuous:
            return try await continueControlled(
                started
            )
        }
    }

    /// Request a cooperative pause for a policy-controlled continuous run.
    ///
    /// The current tool invocation is never cancelled. If it is already
    /// executing, this only records intent; the continuous driver observes the
    /// request after that invocation returns and before starting the next one.
    @discardableResult
    public func requestPause(
        runID: String
    ) -> Bool {
        guard busyRunIDs.contains(runID),
              pauseEligibleRunIDs.contains(runID),
              executionPoliciesByRunID[runID] == .continuous
        else {
            return false
        }

        pauseRequestedRunIDs.insert(
            runID
        )
        return true
    }

    /// Resume a voluntarily paused serial run under the selected policy.
    public func resume(
        runID: String,
        expectedRevision: Int,
        executionPolicy: AgentToolPlanExecutionPolicy
    ) async throws -> AgentToolPlanRun {
        let run = try currentRun(
            id: runID,
            expectedRevision: expectedRevision
        )

        try reserveExistingRun(
            runID
        )
        executionPoliciesByRunID[runID] = executionPolicy

        if executionPolicy == .continuous {
            pauseEligibleRunIDs.insert(
                runID
            )
        }

        defer {
            busyRunIDs.remove(
                runID
            )
            pauseEligibleRunIDs.remove(
                runID
            )
            pauseRequestedRunIDs.remove(
                runID
            )
        }

        try requireNoActiveRecovery(
            for: run
        )

        let updated: AgentToolPlanRun

        switch executionPolicy {
        case .single_step:
            updated = try await executor.resume(
                run,
                executionPolicy: .single_step,
                context: context,
                approvalHandler: approvalHandler
            )
            replace(
                updated
            )

        case .continuous:
            updated = try await continueControlled(
                run
            )
        }

        return updated
    }

    /// Execute a child recovery plan while leaving its parent untouched.
    ///
    /// Recovery plans are ordinary AgentToolPlan runs. If a recovery plan
    /// suspends, it can itself become the parent of another recovery plan.
    /// Successful recovery does not imply that the failed parent node should be
    /// retried or skipped; that remains an explicit caller decision.
    public func recover(
        parentRunID: String,
        expectedParentRevision: Int,
        plan: AgentToolPlan,
        runID: String = UUID().uuidString
    ) async throws -> AgentToolPlanRun {
        let parent = try currentRun(
            id: parentRunID,
            expectedRevision: expectedParentRevision
        )

        try requireRecoverableParent(
            parent
        )
        try requireNoActiveRecovery(for: parent)
        try requireRecoveryDepthAvailable(for: parent)

        try reserveExistingRun(
            parentRunID
        )

        do {
            try reserveNewRun(
                runID
            )
        } catch {
            busyRunIDs.remove(
                parentRunID
            )
            throw error
        }

        defer {
            busyRunIDs.remove(
                parentRunID
            )
            busyRunIDs.remove(
                runID
            )
        }

        let recovery = try await executor.start(
            plan,
            runID: runID,
            relationship: .recovery(
                parentRunID: parentRunID
            ),
            context: context,
            approvalHandler: approvalHandler
        )

        storeNew(
            recovery
        )
        recoveryParentRevisionsByRunID[recovery.id] = parent.revision

        return recovery
    }

    public func run(
        id: String
    ) throws -> AgentToolPlanRun {
        guard let run = runsByID[id] else {
            throw AgentToolPlanRunCoordinatorError.missingRun(
                id
            )
        }

        return run
    }

    public func runs() -> [AgentToolPlanRun] {
        runOrder.compactMap { runID in
            runsByID[runID]
        }
    }

    public func recoveries(
        of parentRunID: String
    ) -> [AgentToolPlanRun] {
        runs().filter { run in
            guard case .recovery(
                parentRunID: let candidateParentRunID
            ) = run.relationship else {
                return false
            }

            return candidateParentRunID == parentRunID
        }
    }

    public func recoveryDepth(
        of runID: String
    ) throws -> Int {
        var depth = 0
        var candidate = try requiredRun(id: runID)

        while case .recovery(parentRunID: let parentRunID) = candidate.relationship {
            depth += 1
            candidate = try requiredRun(id: parentRunID)
        }

        return depth
    }

    public func activeRecovery(
        of parentRunID: String
    ) throws -> AgentToolPlanRun? {
        activeRecovery(for: try requiredRun(id: parentRunID))
    }

    public func isBusy(
        runID: String
    ) -> Bool {
        busyRunIDs.contains(
            runID
        )
    }

    public func retry(
        runID: String,
        expectedRevision: Int
    ) async throws -> AgentToolPlanRun {
        let run = try currentRun(
            id: runID,
            expectedRevision: expectedRevision
        )

        try requireNoActiveRecovery(for: run)
        try reserveExistingRun(
            runID
        )
        defer {
            busyRunIDs.remove(
                runID
            )
        }

        let retried = try await executor.retry(
            run,
            context: context,
            approvalHandler: approvalHandler
        )
        let updated = try await settle(
            retried,
            executionPolicy: executionPoliciesByRunID[runID]
                ?? .continuous
        )

        replace(
            updated
        )

        return updated
    }

    public func decide(
        runID: String,
        expectedRevision: Int,
        decision: ApprovalDecision
    ) async throws -> AgentToolPlanRun {
        let run = try currentRun(
            id: runID,
            expectedRevision: expectedRevision
        )

        guard case .suspended(let suspension) = run.state,
              case .human_review = suspension.reason
        else {
            throw ApprovalError.notPending(
                runID
            )
        }

        try requireNoActiveRecovery(
            for: run
        )
        try reserveExistingRun(
            runID
        )
        defer {
            busyRunIDs.remove(
                runID
            )
        }

        let decided = try await executor.retry(
            run,
            context: context,
            approvalHandler: FixedApproval(
                decision: decision
            )
        )
        let updated = try await settle(
            decided,
            executionPolicy: executionPoliciesByRunID[runID]
                ?? .continuous
        )

        replace(
            updated
        )
        return updated
    }

    public func skip(
        runID: String,
        expectedRevision: Int
    ) async throws -> AgentToolPlanRun {
        let run = try currentRun(
            id: runID,
            expectedRevision: expectedRevision
        )

        try requireNoActiveRecovery(for: run)
        try reserveExistingRun(
            runID
        )
        defer {
            busyRunIDs.remove(
                runID
            )
        }

        let skipped = try executor.skip(
            run
        )
        let updated = try await settle(
            skipped,
            executionPolicy: executionPoliciesByRunID[runID]
                ?? .continuous
        )

        replace(
            updated
        )

        return updated
    }

    public func resume(
        runID: String,
        expectedRevision: Int
    ) async throws -> AgentToolPlanRun {
        let run = try currentRun(
            id: runID,
            expectedRevision: expectedRevision
        )

        try reserveExistingRun(
            runID
        )
        defer {
            busyRunIDs.remove(
                runID
            )
        }

        try requireNoActiveRecovery(for: run)

        let updated = try await executor.resume(
            run,
            context: context,
            approvalHandler: approvalHandler
        )

        replace(
            updated
        )

        return updated
    }
}

private struct FixedApproval: ToolApprovalHandler {
    let decision: ApprovalDecision

    func decide(
        on preflight: ToolPreflight,
        requirement: ApprovalRequirement
    ) async throws -> ApprovalDecision {
        decision
    }

    func decide(
        on review: ToolInvocation.Review
    ) async throws -> ApprovalDecision {
        decision
    }
}

private enum ApprovalError:
    Error,
    LocalizedError
{
    case notPending(String)

    var errorDescription: String? {
        switch self {
        case .notPending(let runID):
            return "AgentToolPlanRun '\(runID)' is not awaiting approval."
        }
    }
}

private extension AgentToolPlanRunCoordinator {
    func requiredRun(id: String) throws -> AgentToolPlanRun {
        guard let run = runsByID[id] else {
            throw AgentToolPlanRunCoordinatorError.missingRun(id)
        }
        return run
    }

    func currentRun(
        id: String,
        expectedRevision: Int
    ) throws -> AgentToolPlanRun {
        let run = try requiredRun(id: id)

        guard run.revision == expectedRevision else {
            throw AgentToolPlanRunCoordinatorError.staleRevision(
                runID: id,
                expected: expectedRevision,
                actual: run.revision
            )
        }

        return run
    }

    func activeRecovery(for parent: AgentToolPlanRun) -> AgentToolPlanRun? {
        for runID in runOrder.reversed() {
            guard recoveryParentRevisionsByRunID[runID] == parent.revision,
                  let run = runsByID[runID],
                  case .recovery(
                    parentRunID: let candidateParentRunID
                  ) = run.relationship,
                  candidateParentRunID == parent.id,
                  !isTerminal(run)
            else {
                continue
            }
            return run
        }
        return nil
    }

    func requireNoActiveRecovery(for parent: AgentToolPlanRun) throws {
        guard let child = activeRecovery(for: parent) else { return }
        throw AgentToolPlanRunCoordinatorError.activeRecoveryChild(
            parentRunID: parent.id,
            childRunID: child.id
        )
    }

    func requireRecoveryDepthAvailable(for parent: AgentToolPlanRun) throws {
        guard try recoveryDepth(of: parent.id) + 1 <= maximumRecoveryDepth else {
            throw AgentToolPlanRunCoordinatorError.maximumRecoveryDepthExceeded(
                parentRunID: parent.id,
                maximumDepth: maximumRecoveryDepth
            )
        }
    }

    func isTerminal(_ run: AgentToolPlanRun) -> Bool {
        switch run.state {
        case .completed, .stopped:
            return true

        case .paused, .suspended:
            return false
        }
    }

    func requireRecoverableParent(
        _ parent: AgentToolPlanRun
    ) throws {
        guard case .suspended(let suspension) = parent.state else {
            throw AgentToolPlanRunCoordinatorError
                .recoveryParentNotSuspended(
                    parent.id
                )
        }

        switch suspension.reason {
        case .failure:
            return

        case .continuation_required:
            throw AgentToolPlanRunCoordinatorError
                .recoveryParentAlreadyResolved(
                    parent.id
                )

        case .human_review:
            throw AgentToolPlanRunCoordinatorError
                .recoveryParentNotSuspended(
                    parent.id
                )
        }
    }

    func reserveNewRun(
        _ runID: String
    ) throws {
        guard runsByID[runID] == nil,
              !busyRunIDs.contains(runID)
        else {
            throw AgentToolPlanRunCoordinatorError.duplicateRunID(
                runID
            )
        }

        busyRunIDs.insert(
            runID
        )
    }

    func reserveExistingRun(
        _ runID: String
    ) throws {
        guard !busyRunIDs.contains(runID) else {
            throw AgentToolPlanRunCoordinatorError.runBusy(
                runID
            )
        }

        busyRunIDs.insert(
            runID
        )
    }

    func storeNew(
        _ run: AgentToolPlanRun
    ) {
        runsByID[run.id] = run
        runOrder.append(
            run.id
        )
    }

    func replace(
        _ run: AgentToolPlanRun
    ) {
        runsByID[run.id] = run
    }

    func continueControlled(
        _ run: AgentToolPlanRun
    ) async throws -> AgentToolPlanRun {
        var current = run

        while case .paused = current.state {
            if pauseRequestedRunIDs.remove(
                current.id
            ) != nil {
                current = requestedPause(
                    current
                )
                replace(
                    current
                )
                return current
            }

            current = try await executor.resume(
                current,
                executionPolicy: .single_step,
                context: context,
                approvalHandler: approvalHandler
            )
            replace(
                current
            )
        }

        return current
    }

    func requestedPause(
        _ run: AgentToolPlanRun
    ) -> AgentToolPlanRun {
        guard case .paused(let pause) = run.state else {
            return run
        }

        return AgentToolPlanRun(
            id: run.id,
            plan: run.plan,
            relationship: run.relationship,
            attempts: run.attempts,
            resolutions: run.resolutions,
            revision: run.revision,
            state: .paused(
                AgentToolPlanPause(
                    afterPath: pause.afterPath,
                    afterCallID: pause.afterCallID,
                    attemptNumber: pause.attemptNumber,
                    reason: .requested
                )
            )
        )
    }
}
