import AgenticInterfaces
import AgenticRuntime

package struct AgenticConversationRunProjection {
    package var run: AgenticHostConsoleRunPresentation
    package var documents: [AgenticHostConsoleDocumentPresentation]

    package static func project(
        _ result: AgentRunResult,
        title: String
    ) -> Self {
        var order: [String] = []
        var eventsByCallID: [String: [AgentRunEvent]] = [:]

        for event in result.events {
            guard let callID = event.toolCallID else {
                continue
            }

            if eventsByCallID[callID] == nil {
                order.append(callID)
            }
            eventsByCallID[callID, default: []].append(event)
        }

        var documents: [AgenticHostConsoleDocumentPresentation] = []
        var steps = order.compactMap { callID -> AgenticHostConsoleStepPresentation? in
            guard let events = eventsByCallID[callID] else {
                return nil
            }

            let title = events.compactMap(\.toolName).last ?? callID
            let state = stepState(for: events)
            let detail = events.last?.summary
            let body = events.map {
                "[iteration \($0.iteration)] \($0.kind.rawValue): \($0.summary)"
            }.joined(separator: "\n")

            documents.append(
                .init(
                    id: "\(result.sessionID)-\(callID)-details",
                    runID: result.sessionID,
                    stepID: callID,
                    kind: .details,
                    body: body
                )
            )

            return .init(
                id: callID,
                title: title,
                detail: detail,
                state: state,
                fields: [
                    .init("outcome", state.rawValue),
                    .init("events", String(events.count)),
                    .init("iteration", String(events.map(\.iteration).max() ?? 0)),
                ]
            )
        }

        if steps.isEmpty {
            let failed = result.events.contains {
                $0.kind == .model_stream_failed
            }
            let state: AgenticHostConsoleStepState = failed ? .failed : .completed
            let body = result.events.map {
                "[iteration \($0.iteration)] \($0.kind.rawValue): \($0.summary)"
            }.joined(separator: "\n")
            let stepID = "\(result.sessionID)-model"

            steps = [
                .init(
                    id: stepID,
                    title: "model response",
                    detail: result.response?.message.content.text,
                    state: state,
                    fields: [
                        .init("outcome", state.rawValue),
                        .init("events", String(result.events.count)),
                    ]
                ),
            ]
            documents.append(
                .init(
                    id: "\(stepID)-details",
                    runID: result.sessionID,
                    stepID: stepID,
                    kind: .details,
                    body: body
                )
            )
        }

        return .init(
            run: .init(
                id: result.sessionID,
                title: title,
                summary: result.response?.message.content.text,
                state: runState(for: result),
                steps: steps
            ),
            documents: documents
        )
    }

    private static func runState(
        for result: AgentRunResult
    ) -> AgenticHostConsoleRunState {
        if result.isAwaitingApproval {
            return .awaitingApproval
        }
        if result.isSuspended {
            return .paused
        }
        if result.events.contains(where: {
            $0.kind == .model_stream_failed || $0.kind == .tool_error
        }) {
            return .failed
        }
        return .completed
    }

    private static func stepState(
        for events: [AgentRunEvent]
    ) -> AgenticHostConsoleStepState {
        if events.contains(where: { $0.kind == .tool_error }) {
            return .failed
        }
        if events.contains(where: {
            $0.kind == .tool_denied || $0.kind == .tool_skipped
        }) {
            return .skipped
        }
        if events.contains(where: { $0.kind == .tool_result }) {
            return .completed
        }
        return .active
    }
}
