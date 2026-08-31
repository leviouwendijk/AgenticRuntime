import AgenticInterfaces

struct HostActivity:
    Sendable,
    Hashable
{
    var runID: String?
    var stepID: String?
    var label: String

    init(
        runID: String? = nil,
        stepID: String? = nil,
        label: String
    ) {
        self.runID = runID
        self.stepID = stepID
        self.label = label
    }

    static let load = HostActivity(
        label: "loading ToolPlan"
    )

    static func action(
        _ action: AgenticHostConsoleAction,
        runID: String,
        stepID: String
    ) -> HostActivity {
        let label: String

        switch action {
        case .approve:
            label = "applying approval"

        case .deny:
            label = "applying denial"

        case .skip:
            label = "skipping step"

        case .continueRun:
            label = "continuing run"

        case .stopRun:
            label = "stopping run"

        case .retry:
            label = "retrying step"

        case .createFixBranch:
            label = "starting recovery"
        }

        return HostActivity(
            runID: runID,
            stepID: stepID,
            label: label
        )
    }

    func note(
        frame: Int
    ) -> String {
        let frames = [
            "⠋",
            "⠙",
            "⠹",
            "⠸",
            "⠼",
            "⠴",
            "⠦",
            "⠧",
            "⠇",
            "⠏",
        ]

        return "\(frames[frame % frames.count]) \(label)"
    }

    func project(
        _ source: AgenticHostConsoleSnapshot
    ) -> AgenticHostConsoleSnapshot {
        guard let runID else {
            return source
        }

        var snapshot = source

        snapshot.interruptions.removeAll {
            $0.runID == runID
        }

        guard let runIndex = snapshot.runs.firstIndex(
            where: {
                $0.id == runID
            }
        ) else {
            return snapshot
        }

        snapshot.runs[runIndex].state = .active

        if let stepID,
           let stepIndex = snapshot.runs[runIndex].steps.firstIndex(
            where: {
                $0.id == stepID
            }
           ) {
            snapshot.runs[runIndex].steps[stepIndex].state = .active
        }

        return snapshot
    }
}

actor HostWork {
    private var activity: HostActivity?
    private var completion: String?
    private var pausePendingRunIDs: Set<String> = []

    func begin(
        _ activity: HostActivity
    ) -> Bool {
        guard self.activity == nil,
              completion == nil else {
            return false
        }

        self.activity = activity
        return true
    }

    func current() -> HostActivity? {
        activity
    }

    func markPausePending(
        runID: String
    ) -> Bool {
        guard activity?.runID == runID else {
            return false
        }

        pausePendingRunIDs.insert(
            runID
        )
        return true
    }

    func project(
        _ source: AgenticHostConsoleSnapshot
    ) -> AgenticHostConsoleSnapshot {
        var snapshot = activity?.project(
            source
        ) ?? source

        for runID in pausePendingRunIDs {
            guard let runIndex = snapshot.runs.firstIndex(
                where: {
                    $0.id == runID
                }
            ) else {
                continue
            }

            snapshot.runs[runIndex].state = .pause_pending
        }

        return snapshot
    }

    func finish(
        _ note: String
    ) {
        if let runID = activity?.runID {
            pausePendingRunIDs.remove(
                runID
            )
        }

        activity = nil
        completion = note
    }

    func takeCompletion() -> String? {
        guard let completion else {
            return nil
        }

        self.completion = nil
        return completion
    }
}
