import Agentic
import AgenticExecution
import AgenticInterfaces
import AgenticRuntime
import Clipboard
import Foundation
import Terminal

enum HostConsoleError:
    Error,
    LocalizedError
{
    case toolPlanRequired

    var errorDescription: String? {
        switch self {
        case .toolPlanRequired:
            return "Clipboard input must contain an AgentToolPlan invocation."
        }
    }
}

enum HostConsole {
    static func run(
        host: AgenticToolHost,
        context: String
    ) async throws {
        let coordinator = AgentToolPlanRunCoordinator(
            invoker: host.invoker,
            context: host.context,
            approvalHandler: nil
        )
        let stream = TerminalStream.standardError
        let session = try TerminalSession(
            options: TerminalSession.Options(
                useAlternateScreen: true,
                hideCursor: true,
                useRawMode: true,
                useBracketedPaste: true,
                restoreOnInterrupt: true,
                outputStream: stream
            )
        )

        defer {
            session.restore()
        }

        let reader = TerminalKeyReader()
        var renderer = TerminalFrameRenderer(
            stream: stream
        )
        var size = Terminal.size(
            for: stream
        )
        var note = "p load clipboard ToolPlan"
        var console = AgenticHostConsoleWorkflowControl(
            snapshot: HostProjection.snapshot(
                runs: [],
                context: context,
                note: note
            )
        )

        func render() {
            var frame = TerminalFrame(
                rows: size.rows,
                columns: size.columns
            )

            console.render(
                into: &frame,
                in: TerminalRegion(
                    rows: size.rows,
                    columns: size.columns
                )
            )
            renderer.render(
                frame
            )
        }

        render()

        while true {
            let events = reader.readEvents(
                timeoutMilliseconds: 100,
                maximumCount: 128
            )

            if events.isEmpty {
                let currentSize = Terminal.size(
                    for: stream
                )

                if currentSize != size {
                    size = currentSize
                    render()
                }

                continue
            }

            var shouldExit = false

            for event in events {
                guard case .key(let key) = event else {
                    continue
                }

                if key == .char("p"),
                   console.focus.current == .base {
                    do {
                        try await load(
                            host: host,
                            coordinator: coordinator
                        )
                        note = "ToolPlan loaded"
                    } catch {
                        note = error.localizedDescription
                    }

                    console.update(
                        HostProjection.snapshot(
                            runs: await coordinator.runs(),
                            context: context,
                            note: note
                        )
                    )
                    continue
                }

                if let event = console.handle(
                    key
                ) {
                    if event.requestsExit {
                        shouldExit = true
                        break
                    }

                    if case .actionRequested(
                        interruptionID: _,
                        runID: let runID,
                        stepID: _,
                        action: let action
                    ) = event {
                        do {
                            try await apply(
                                action,
                                runID: runID,
                                host: host,
                                coordinator: coordinator
                            )
                            note = "Action applied"
                        } catch {
                            note = error.localizedDescription
                        }

                        console.update(
                            HostProjection.snapshot(
                                runs: await coordinator.runs(),
                                context: context,
                                note: note
                            )
                        )
                    }
                }
            }

            if shouldExit {
                return
            }

            size = Terminal.size(
                for: stream
            )
            render()
        }
    }
}

private extension HostConsole {
    static func load(
        host: AgenticToolHost,
        coordinator: AgentToolPlanRunCoordinator
    ) async throws {
        _ = try await coordinator.start(
            plan(
                host: host
            )
        )
    }

    static func apply(
        _ action: AgenticHostConsoleAction,
        runID: String,
        host: AgenticToolHost,
        coordinator: AgentToolPlanRunCoordinator
    ) async throws {
        guard let run = await coordinator.runs().first(
            where: {
                $0.id == runID
            }
        ) else {
            throw AgentToolPlanRunCoordinatorError.missingRun(
                runID
            )
        }

        switch action {
        case .retry:
            _ = try await coordinator.retry(
                runID: runID,
                expectedRevision: run.revision
            )

        case .skip:
            _ = try await coordinator.skip(
                runID: runID,
                expectedRevision: run.revision
            )

        case .continueRun:
            _ = try await coordinator.resume(
                runID: runID,
                expectedRevision: run.revision
            )

        case .approve:
            _ = try await coordinator.decide(
                runID: runID,
                expectedRevision: run.revision,
                decision: .approved
            )

        case .deny:
            _ = try await coordinator.decide(
                runID: runID,
                expectedRevision: run.revision,
                decision: .denied
            )

        case .createFixBranch:
            _ = try await coordinator.recover(
                parentRunID: runID,
                expectedParentRevision: run.revision,
                plan: plan(
                    host: host
                )
            )

        case .stopRun:
            return
        }
    }

    static func plan(
        host: AgenticToolHost
    ) throws -> AgentToolPlan {
        guard let text = Clipboard.system.read(),
              !text.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty
        else {
            throw AgenticRuntimeCommandError
                .missingClipboardInput
        }

        let request = try host.decodeInvocationRequest(
            Data(
                text.utf8
            )
        )

        guard request.action == .invoke,
              let plan = request.plan
        else {
            throw HostConsoleError.toolPlanRequired
        }

        return plan
    }
}
