import Agentic
import AgenticPrograms
import Foundation
import Primitives

struct AgentProgramRecordingUserInputInvoker:
    AgentProgramUserInputInvoking
{
    let trace: AgentProgramExecutionTrace
    let resumeControl: AgentProgramResumeControl?

    func ask(
        _ request: UserInputRequest
    ) async throws -> UserInputResponse {
        let inputValue = try JSONToolBridge.encode(
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
                throw AgentProgramReplayError.invalid_completed_step(
                    index: index
                )
            }

            let reply = try JSONToolBridge.decode(
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
            let outputValue = try JSONToolBridge.encode(
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

        let suspension = AgentSuspension.user_input(
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

        throw AgentProgramSuspensionSignal(
            suspension: suspension
        )
    }
}
