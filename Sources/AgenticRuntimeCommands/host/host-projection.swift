import Agentic
import AgenticExecution
import AgenticInterfaces
import AgenticRuntime
import Terminal

enum HostProjection {
    static func snapshot(
        runs: [AgentToolPlanRun],
        context: String,
        note: String? = nil
    ) -> AgenticHostConsoleSnapshot {
        let context = [
            context,
            note,
        ]
            .compactMap { value in
                guard let value,
                      !value.isEmpty else {
                    return nil
                }

                return value
            }
            .joined(
                separator: " · "
            )

        return AgenticHostConsoleSnapshot(
            context: context,
            runs: runs.map(
                makeRun
            ),
            interruptions: runs.compactMap(
                makeInterruption
            ),
            documents: runs.flatMap(
                makeDocs
            )
        )
    }
}

private extension HostProjection {
    static func makeInterruption(
        _ run: AgentToolPlanRun
    ) -> AgenticHostConsoleInterruptionPresentation? {
        guard case .suspended(let suspension) = run.state else {
            return nil
        }

        let kind: AgenticHostConsoleInterruptionKind
        let title: String
        let summary: String
        let actions: [AgenticHostConsoleAction]

        switch suspension.reason {
        case .failure(let errorDescription):
            kind = .recovery
            title = "Recovery"
            summary =
                errorDescription
                ?? "The current ToolPlan step failed."
            actions = [
                .retry,
                .skip,
                .createFixBranch,
            ]

        case .human_review:
            kind = .approval
            title = "Approval"
            summary = "This ToolPlan step requires human approval."
            actions = [
                .approve,
                .deny,
                .skip,
            ]

        case .continuation_required:
            kind = .recovery
            title = "Continue"
            summary = "The interrupted step is resolved. Continue the remaining ToolPlan?"
            actions = [
                .continueRun,
            ]
        }

        return AgenticHostConsoleInterruptionPresentation(
            id: "\(run.id):\(run.revision)",
            runID: run.id,
            stepID: suspension.callID,
            kind: kind,
            title: title,
            summary: summary,
            actions: actions
        )
    }

    static func makeRun(
        _ run: AgentToolPlanRun
    ) -> AgenticHostConsoleRunPresentation {
        AgenticHostConsoleRunPresentation(
            id: run.id,
            title: run.plan.id,
            summary: summary(
                run
            ),
            state: state(
                run
            ),
            steps: records(
                run
            ).map(
                makeStep
            )
        )
    }

    static func makeStep(
        _ record: AgentToolPlanRecord
    ) -> AgenticHostConsoleStepPresentation {
        let review = record.invocation?.review
        let targets = review?.preflight.targetPaths ?? []
        let detail = targets.first.map { first in
            targets.count > 1
                ? "\(first) (+\(targets.count - 1))"
                : first
        }

        var fields = [
            AgenticHostConsoleField(
                "outcome",
                outcome(
                    record.outcome
                )
            ),
        ]

        if let review {
            let preflight = review.preflight

            fields.append(
                .init(
                    "requirement",
                    review.requirement.rawValue
                )
            )
            fields.append(
                .init(
                    "risk",
                    preflight.risk.rawValue
                )
            )

            if !targets.isEmpty {
                fields.append(
                    .init(
                        targets.count == 1
                            ? "target"
                            : "targets",
                        targets.joined(
                            separator: ", "
                        )
                    )
                )
            }

            if !preflight.summary.isEmpty {
                fields.append(
                    .init(
                        "summary",
                        preflight.summary
                    )
                )
            }

            if let preview = preflight.diffPreview {
                fields.append(
                    .init(
                        "changes",
                        "+\(preview.insertedLineCount) -\(preview.deletedLineCount)"
                    )
                )
            }
        }

        if let error = record.errorDescription,
           !error.isEmpty {
            fields.append(
                .init(
                    "error",
                    error
                )
            )
        }

        if let reason = record.skipReason,
           !reason.isEmpty {
            fields.append(
                .init(
                    "skip",
                    reason
                )
            )
        }

        return AgenticHostConsoleStepPresentation(
            id: record.call.id,
            title: record.call.name,
            detail: detail,
            state: state(
                record.outcome
            ),
            fields: fields
        )
    }

    static func makeDocs(
        _ run: AgentToolPlanRun
    ) -> [AgenticHostConsoleDocumentPresentation] {
        records(
            run
        ).flatMap { record -> [AgenticHostConsoleDocumentPresentation] in
            guard let invocation = record.invocation else {
                return []
            }

            let review = invocation.review
            let preflight = review.preflight
            let inspection = preflight.inspectionDocument(
                title: "Staged intent details",
                toolName: record.call.name,
                toolCallID: record.call.id,
                requirement: review.requirement
            )
            let details = AgenticTerminalInspectionRenderer.render(
                inspection,
                stream: .standardError,
                theme: .agentic,
                layout: .agentic
            )

            var docs = [
                AgenticHostConsoleDocumentPresentation(
                    id: "\(run.id):\(record.call.id):details",
                    runID: run.id,
                    stepID: record.call.id,
                    kind: .details,
                    title: "Staged intent details",
                    body: details
                ),
            ]

            if let preview = preflight.diffPreview,
               !preview.isEmpty {
                let body: String

                if let layout = preview.layout {
                    body = TerminalDifferenceRenderer.render(
                        layout
                    )
                } else {
                    body = preview.text
                }

                docs.append(
                    AgenticHostConsoleDocumentPresentation(
                        id: "\(run.id):\(record.call.id):diff",
                        runID: run.id,
                        stepID: record.call.id,
                        kind: .diff,
                        title: preview.title ?? "Diff preview",
                        body: body
                    )
                )
            }

            return docs
        }
    }

    static func summary(
        _ run: AgentToolPlanRun
    ) -> String {
        let relationship: String

        switch run.relationship {
        case .root:
            relationship = "root"

        case .recovery(
            parentRunID: let parentID
        ):
            relationship = "recovery of \(parentID)"
        }

        return "\(relationship) · rev \(run.revision)"
    }

    static func state(
        _ run: AgentToolPlanRun
    ) -> AgenticHostConsoleRunState {
        switch run.state {
        case .completed:
            return .completed

        case .paused:
            return .paused

        case .stopped(let outcome):
            switch outcome {
            case .succeeded:
                return .completed

            default:
                return .failed
            }

        case .suspended(let suspension):
            switch suspension.reason {
            case .human_review:
                return .awaitingApproval

            case .failure,
                 .continuation_required:
                return .onHold
            }
        }
    }

    static func state(
        _ outcome: AgentToolPlanOutcome
    ) -> AgenticHostConsoleStepState {
        switch outcome {
        case .succeeded:
            return .completed

        case .needs_human_review:
            return .active

        case .skipped:
            return .skipped

        case .failed,
             .denied,
             .mixed:
            return .failed
        }
    }

    static func outcome(
        _ outcome: AgentToolPlanOutcome
    ) -> String {
        switch outcome {
        case .succeeded:
            return "succeeded"

        case .failed:
            return "failed"

        case .denied:
            return "denied"

        case .needs_human_review:
            return "needs human review"

        case .skipped:
            return "skipped"

        case .mixed:
            return "mixed"
        }
    }

    static func records(
        _ run: AgentToolPlanRun
    ) -> [AgentToolPlanRecord] {
        var paths: [String] = []
        var byPath: [String: AgentToolPlanRecord] = [:]

        for attempt in run.attempts {
            for record in attempt.result.records {
                if byPath[record.path] == nil {
                    paths.append(
                        record.path
                    )
                }

                byPath[record.path] = record
            }
        }

        for resolution in run.resolutions {
            guard case .skipped = resolution.kind,
                  let record = byPath[resolution.path]
            else {
                continue
            }

            byPath[resolution.path] = AgentToolPlanRecord(
                path: resolution.path,
                call: record.call,
                outcome: .skipped,
                invocation: record.invocation,
                skipReason: "explicit_run_resolution"
            )
        }

        return paths.compactMap { path in
            byPath[path]
        }
    }
}
