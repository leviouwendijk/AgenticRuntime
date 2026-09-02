import Agentic
import AgenticInterfaces
import AgenticRuntime
import TestFlows

private enum RuntimeVoiceInputFixtureFailure:
    Error
{
    case missingProvider
}

private actor RuntimeVoiceInputFixture:
    VoiceInputProvider
{
    func availability() async
        -> AgenticConversationVoice.Availability
    {
        .available
    }

    func start() async throws {}

    func stop() async throws
        -> AgenticConversationTranscription
    {
        .init(
            text: "voice fixture",
            localeIdentifier: "en-US"
        )
    }

    func cancel() async {}
}

extension AgenticRuntimeFlowTesting {
    static func runVoiceInputProvider()
        async throws
        -> [TestFlowDiagnostic]
    {
        let provider = RuntimeVoiceInputFixture()

        let application = Agentic.application(
            "voice-runtime-fixture"
        ) {
            voiceInput(
                provider
            )
        }

        guard let configured =
            application.voiceInputProvider
        else {
            throw RuntimeVoiceInputFixtureFailure
                .missingProvider
        }

        let availability =
            await configured.availability()

        try Expect.equal(
            availability,
            .available,
            "voice-input.availability"
        )

        let transcription =
            try await configured.stop()

        try Expect.equal(
            transcription.text,
            "voice fixture",
            "voice-input.transcription"
        )

        try Expect.equal(
            transcription.localeIdentifier,
            "en-US",
            "voice-input.locale"
        )

        return []
    }
}
