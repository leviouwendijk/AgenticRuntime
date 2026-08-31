import Agentic
import AgenticInterfaces

actor HostPendingPlans {
    private var plansByRunID: [String: AgentToolPlan] = [:]
    private var runOrder: [String] = []

    func insert(
        _ plan: AgentToolPlan,
        runID: String
    ) {
        if plansByRunID[runID] == nil {
            runOrder.append(
                runID
            )
        }

        plansByRunID[runID] = plan
    }

    func plan(
        runID: String
    ) -> AgentToolPlan? {
        plansByRunID[runID]
    }

    func take(
        runID: String
    ) -> AgentToolPlan? {
        guard let plan = plansByRunID.removeValue(
            forKey: runID
        ) else {
            return nil
        }

        runOrder.removeAll {
            $0 == runID
        }

        return plan
    }

    func restore(
        _ plan: AgentToolPlan,
        runID: String
    ) {
        insert(
            plan,
            runID: runID
        )
    }

    func presentations() -> [AgenticHostConsoleRunPresentation] {
        runOrder.compactMap { runID in
            guard let plan = plansByRunID[runID] else {
                return nil
            }

            return Self.presentation(
                plan,
                runID: runID
            )
        }
    }
}

private extension HostPendingPlans {
    static func presentation(
        _ plan: AgentToolPlan,
        runID: String
    ) -> AgenticHostConsoleRunPresentation {
        AgenticHostConsoleRunPresentation(
            id: runID,
            title: plan.id,
            summary: "Awaiting execution policy.",
            state: .ready,
            steps: steps(
                plan.root,
                path: "root"
            )
        )
    }

    static func steps(
        _ node: AgentToolPlanNode,
        path: String
    ) -> [AgenticHostConsoleStepPresentation] {
        switch node {
        case .call(
            let call,
            _,
            let onSuccess,
            let onFailure,
            let onDenied
        ):
            var result = [
                AgenticHostConsoleStepPresentation(
                    id: call.id,
                    title: call.name,
                    state: .pending
                ),
            ]

            result.append(
                contentsOf: steps(
                    onSuccess,
                    path: "\(path).onSuccess"
                )
            )
            result.append(
                contentsOf: steps(
                    onFailure,
                    path: "\(path).onFailure"
                )
            )
            result.append(
                contentsOf: steps(
                    onDenied,
                    path: "\(path).onDenied"
                )
            )

            return result

        case .sequence(let children):
            return steps(
                children,
                path: "\(path).sequence"
            )

        case .batch(let children):
            return steps(
                children,
                path: "\(path).batch"
            )
        }
    }

    static func steps(
        _ nodes: [AgentToolPlanNode],
        path: String
    ) -> [AgenticHostConsoleStepPresentation] {
        nodes.enumerated().flatMap { index, node in
            steps(
                node,
                path: "\(path)[\(index)]"
            )
        }
    }
}
