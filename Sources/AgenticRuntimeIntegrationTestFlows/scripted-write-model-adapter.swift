import AgenticIO
import Agentic

struct ScriptedWriteModelAdapter: AgentModelAdapter {
    let path: String
    let content: String

    var response: AgentModelResponseProviding {
        ScriptedWriteModelResponseProvider(
            path: path,
            content: content
        )
    }
}

struct ScriptedWriteModelResponseProvider: AgentModelResponseProviding {
    let path: String
    let content: String

    func buffered(
        request: AgentRequest
    ) async throws -> AgentResponse {
        if let toolResult = latestToolResult(
            in: request
        ) {
            return .init(
                message: .init(
                    role: .assistant,
                    text: finalMessage(
                        from: toolResult
                    )
                ),
                stopReason: .end_turn
            )
        }

        let toolCall = AgentToolCall(
            id: "tool-call-write-apple-fragment",
            name: WriteFileTool.identifier.rawValue,
            input: try JSONToolBridge.encode(
                WriteFileToolInput(
                    path: path,
                    content: content
                )
            )
        )

        return .init(
            message: .init(
                role: .assistant,
                content: .init(
                    blocks: [
                        .tool_call(
                            toolCall
                        )
                    ]
                )
            ),
            stopReason: .tool_use
        )
    }

    func stream(
        request: AgentRequest
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await buffered(
                        request: request
                    )

                    continuation.yield(
                        .completed(
                            response
                        )
                    )

                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: error
                    )
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private extension ScriptedWriteModelResponseProvider {
    func latestToolResult(
        in request: AgentRequest
    ) -> AgentToolResult? {
        for message in request.messages.reversed() {
            for block in message.content.blocks.reversed() {
                guard case .tool_result(let result) = block else {
                    continue
                }

                return result
            }
        }

        return nil
    }

    func finalMessage(
        from toolResult: AgentToolResult
    ) -> String {
        if toolResult.isError {
            return "write_file was denied or failed."
        }

        return "write_file completed through AgenticInterfaces approval."
    }
}
