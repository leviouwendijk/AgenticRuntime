import Agentic
import AgenticInterfaces
import AgenticRuntime
import Arguments
import Clipboard
import Terminal

public enum AgenticRuntimeConversationCommand<
    Application: AgenticApplicationProviding
>:
    ParsedArgumentCommand
{
    public typealias Options = HostOptions

    public static var name: String {
        "conversation"
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        _ = invocation

        let runtime = try await AgenticRuntime.resolve(
            Application.self
        )
        var conversation = try AgenticConversationSession(
            runtime: runtime,
            workspacePath: options.workspace,
            sessionID: options.sessionID
        )
        try await AgenticConversationConsole.run(
            conversation: &conversation
        )
    }
}

private enum AgenticConversationConsole {
    static func run(
        conversation: inout AgenticConversationSession
    ) async throws {
        let stream = TerminalStream.standardError
        let terminalSession = try TerminalSession(
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
            terminalSession.restore()
        }

        let reader = TerminalKeyReader()
        var renderer = TerminalFrameRenderer(stream: stream)
        var size = Terminal.size(for: stream)
        var control = AgenticConversationControl(
            snapshot: conversation.snapshot
        )

        func render() {
            var frame = TerminalFrame(
                rows: size.rows,
                columns: size.columns
            )
            control.render(
                into: &frame,
                in: TerminalRegion(
                    rows: size.rows,
                    columns: size.columns
                )
            )
            renderer.render(frame)
        }

        render()

        while true {
            let events = reader.readEvents(
                timeoutMilliseconds: 100,
                maximumCount: 128
            )

            if events.isEmpty {
                let currentSize = Terminal.size(for: stream)
                if currentSize != size {
                    size = currentSize
                    render()
                }
                continue
            }

            for input in events {
                guard let event = control.handle(input) else {
                    continue
                }

                switch event {
                case .exitRequested:
                    return

                case .submissionRequested(let submission):
                    conversation.setActivity("invoking model")
                    control.update(conversation.snapshot)
                    render()

                    do {
                        try await conversation.submit(submission)
                    } catch {
                        conversation.recordFailure(error)
                    }
                    control.update(conversation.snapshot)

                case .modelSelectionChanged(let identifier):
                    conversation.selectModel(identifier)
                    control.update(conversation.snapshot)

                case .skillSelectionChanged(let identifiers):
                    conversation.selectSkills(identifiers)
                    control.update(conversation.snapshot)

                case .feedbackRequested(let message):
                    conversation.setActivity(message)
                    control.update(conversation.snapshot)

                case .run(let workflowEvent):
                    service(
                        workflowEvent,
                        conversation: &conversation
                    )
                    control.update(conversation.snapshot)

                case .contentPinned,
                     .attachmentOpened,
                     .attachmentClosed,
                     .runOpened,
                     .runClosed:
                    break
                }
            }

            size = Terminal.size(for: stream)
            render()
        }
    }

    private static func service(
        _ event: AgenticHostConsoleWorkflowEvent,
        conversation: inout AgenticConversationSession
    ) {
        let copied: Bool
        let success: String
        let failure: String

        switch event {
        case .copyRequested(
            text: let text,
            title: let title
        ):
            copied = Clipboard.system.write(text)
            success = "Copied \(title.lowercased())."
            failure = "Clipboard write failed."

        case .runInputCopyRequested(runID: let runID):
            guard let text = conversation.input(for: runID) else {
                conversation.setActivity("Run input is not available.")
                return
            }
            copied = Clipboard.system.write(text)
            success = "Copied run input."
            failure = "Could not copy run input."

        case .runOutputCopyRequested(runID: let runID):
            guard let text = conversation.output(for: runID) else {
                conversation.setActivity("Run output is not available.")
                return
            }
            copied = Clipboard.system.write(text)
            success = "Copied run output."
            failure = "Could not copy run output."

        case .feedbackRequested(message: let message):
            conversation.setActivity(message)
            return

        default:
            return
        }

        conversation.setActivity(copied ? success : failure)
    }
}
