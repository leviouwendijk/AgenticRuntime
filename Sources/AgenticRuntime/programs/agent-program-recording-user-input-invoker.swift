import Agentic
import Foundation
import Primitives

struct ProgramRecordingUserInputInvoker:
    ProgramUserInputInvoking
{
    let trace: ProgramExecutionTrace
    let resumeControl: ProgramResumeControl?

    func ask(
        _ request: UserInputRequest
    ) async throws -> UserInputResponse {
        let inputValue = try JSONCoding.default.value(
            request
        )
        let index = await trace.reserveIndex()
        let startedAt = Date()

        if let replayed = try await trace.replay(
            index: index,
            kind: .user_input,
            input: inputValue
        ) {
            guard let outputValue = replayed.output else {
                throw ProgramReplayError.invalid_completed_step(
                    index: index
                )
            }

            let reply = try JSONCoding.default.decode(
                UserInputReply.self,
                from: outputValue
            )
            let response = try UserInputResponse(
                reply,
                for: request
            )

            await trace.append(
                replayed
            )
            return response
        }

        if let resumeControl,
           let response = try await resumeControl.userInputResponse(
               at: index,
               request: request
           )
        {
            let outputValue = try JSONCoding.default.value(
                response.reply
            )
            let completedAt = Date()

            await trace.append(
                .init(
                    index: index,
                    kind: .user_input,
                    input: inputValue,
                    output: outputValue,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: agentProgramElapsedMilliseconds(
                        from: startedAt,
                        to: completedAt
                    )
                )
            )

            return response
        }

        let suspension = Run.Suspension.user_input(
            request
        )
        let completedAt = Date()

        await trace.append(
            .init(
                index: index,
                kind: .user_input,
                input: inputValue,
                suspension: suspension,
                startedAt: startedAt,
                completedAt: completedAt,
                durationMilliseconds: agentProgramElapsedMilliseconds(
                    from: startedAt,
                    to: completedAt
                )
            )
        )

        throw ProgramSuspensionSignal(
            suspension: suspension
        )
    }
}
