import AgenticInterfaces

public protocol VoiceInputProvider:
    Sendable
{
    func availability() async
        -> AgenticConversationVoice.Availability

    func status() async
        -> AgenticConversationVoice.Status?

    func start() async throws

    func stop() async throws
        -> AgenticConversationTranscription

    func cancel() async
}


public extension VoiceInputProvider {
    func status() async
        -> AgenticConversationVoice.Status?
    {
        nil
    }
}
