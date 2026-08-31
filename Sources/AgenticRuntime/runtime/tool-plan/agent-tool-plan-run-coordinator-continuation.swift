import AgenticExecution

extension AgentToolPlanRunCoordinator {
    func settle(
        _ run: AgentToolPlanRun,
        executionPolicy: AgentToolPlanExecutionPolicy = .continuous
    ) async throws -> AgentToolPlanRun {
        switch executionPolicy {
        case .continuous:
            var current = run

            while case .suspended(let suspension) = current.state,
                  case .continuation_required = suspension.reason
            {
                current = try await executor.resume(
                    current,
                    context: context,
                    approvalHandler: approvalHandler
                )
            }

            return current

        case .single_step:
            guard case .suspended(let suspension) = run.state,
                  case .continuation_required = suspension.reason
            else {
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
                        afterPath: suspension.path,
                        afterCallID: suspension.callID,
                        attemptNumber: suspension.attemptNumber,
                        reason: .single_step
                    )
                )
            )
        }
    }
}
