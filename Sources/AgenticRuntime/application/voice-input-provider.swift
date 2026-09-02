import AgenticInterfaces

public protocol VoiceInputProvider:
    Sendable
{
    func availability() async
        -> AgenticConversationVoice.Availability

    func start() async throws

    func stop() async throws
        -> AgenticConversationTranscription

    func cancel() async
}
