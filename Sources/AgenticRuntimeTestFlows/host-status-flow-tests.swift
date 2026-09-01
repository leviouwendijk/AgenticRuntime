import AgenticInterfaces
import AgenticRuntimeCommands
import TestFlows

enum AgenticRuntimeHostStatusFlowTesting {
    enum Failure:
        Error
    {
        case workDidNotBegin
        case missingCompletion
        case missingStatus
    }

    static func runPersistentFailureStatus() async throws -> [TestFlowDiagnostic] {
        let work = HostWork()
        let diagnostic = "Automatic continuation from 'root.sequence[1]' is not supported because the next authored operation requires a different execution boundary."

        guard await work.begin(
            runID: "status-run",
            stepID: "status-step",
            label: "executing step"
        ) else {
            throw Failure.workDidNotBegin
        }

        await work.fail(
            diagnostic,
            title: "Execution attempt failed"
        )

        guard let completion = await work.takeCompletion() else {
            throw Failure.missingCompletion
        }

        try Expect.equal(
            completion,
            "Execution attempt failed · Status available",
            "failure completion remains concise"
        )

        let first = await work.project(
            AgenticHostConsoleSnapshot()
        )

        guard let status = first.statuses.first else {
            throw Failure.missingStatus
        }

        try Expect.equal(
            status.runID,
            "status-run",
            "status keeps run association"
        )
        try Expect.equal(
            status.stepID,
            "status-step",
            "status keeps step association"
        )
        try Expect.equal(
            status.kind,
            .error,
            "failure status kind"
        )
        try Expect.equal(
            status.title,
            "Execution attempt failed",
            "failure status title"
        )
        try Expect.equal(
            status.summary,
            "executing step",
            "failure status activity summary"
        )
        try Expect.equal(
            status.body,
            diagnostic,
            "failure status preserves complete diagnostic"
        )

        let second = await work.project(
            AgenticHostConsoleSnapshot()
        )

        try Expect.equal(
            second.statuses,
            first.statuses,
            "status persists after completion is consumed"
        )

        return [
            .field(
                "status",
                status.title
            ),
            .field(
                "persistent",
                "true"
            ),
        ]
    }
}
