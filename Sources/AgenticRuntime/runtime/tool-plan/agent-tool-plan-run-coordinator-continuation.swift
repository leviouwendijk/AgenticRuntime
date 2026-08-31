import AgenticExecution

extension AgentToolPlanRunCoordinator {
    func settle(
        _ run: AgentToolPlanRun
    ) async throws -> AgentToolPlanRun {
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
    }
}
