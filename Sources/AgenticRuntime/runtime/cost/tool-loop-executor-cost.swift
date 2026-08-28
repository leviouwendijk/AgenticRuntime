import Agentic
import AgenticUsage

extension ToolLoopExecutor {
    func applyProjectedCost(
        for request: AgentRequest,
        to checkpoint: inout AgentHistoryCheckpoint,
        turnIndex: Int
    ) async throws {
        guard let costTracker else {
            return
        }

        let record = costTracker.projectedRecord(
            existing: checkpoint.costRecord,
            request: request,
            sessionID: checkpoint.id,
            turnIndex: turnIndex
        )

        checkpoint.costRecord = record

        try await appendRunEvent(
            .init(
                kind: .cost_projected,
                iteration: checkpoint.state.iteration,
                summary: costSummary(
                    phase: "projected",
                    record: record
                )
            ),
            to: &checkpoint
        )
    }

    func applyActualCost(
        for request: AgentRequest,
        response: AgentResponse,
        to checkpoint: inout AgentHistoryCheckpoint,
        turnIndex: Int
    ) async throws {
        guard let costTracker else {
            return
        }

        guard let record = costTracker.actualRecord(
            existing: checkpoint.costRecord,
            request: request,
            response: response,
            sessionID: checkpoint.id,
            turnIndex: turnIndex
        ) else {
            return
        }

        checkpoint.costRecord = record

        try await appendRunEvent(
            .init(
                kind: .cost_actual,
                iteration: checkpoint.state.iteration,
                messageID: response.message.id,
                summary: costSummary(
                    phase: "actual",
                    record: record
                )
            ),
            to: &checkpoint
        )
    }

    func costSummary(
        phase: String,
        record: AgentCostRecord
    ) -> String {
        let projection: AgentCostProjection?

        switch phase {
        case "actual":
            projection = record.actual

        default:
            projection = record.projected
        }

        guard let projection else {
            return "\(phase) cost unavailable"
        }

        var parts: [String] = [
            "\(phase) cost status=\(projection.status.rawValue)"
        ]

        if let amount = projection.amount {
            parts.append(
                "amount=\(amount.currencyCode) \(amount.majorUnitsApproximation)"
            )
        }

        parts.append(
            "tokens=\(projection.usage.totalKnownTokens)"
        )

        if let model = record.model {
            parts.append(
                "model=\(model)"
            )
        }

        if !projection.issues.isEmpty {
            parts.append(
                "issues=\(projection.issues.count)"
            )
        }

        return parts.joined(
            separator: " "
        )
    }
}
